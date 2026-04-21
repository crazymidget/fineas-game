/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    This class manages most of the game logic.
*/

import simd
import SceneKit
import SpriteKit
import QuartzCore
import AVFoundation
import GameController

// Collision bit masks
let BitmaskCollision        = Int(1 << 2)
let BitmaskCollectable      = Int(1 << 3)
let BitmaskEnemy            = Int(1 << 4)
let BitmaskSuperCollectable = Int(1 << 5)
let BitmaskWater            = Int(1 << 6)

#if os(iOS) || os(tvOS)
    typealias ViewController = UIViewController
#elseif os(OSX)
    typealias ViewController = NSViewController
#endif

class GameViewController: ViewController, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
   
    // Game view
    var gameView: GameView {
        return view as! GameView
    }
    
    // Nodes to manipulate the camera
    private let cameraYHandle = SCNNode()
    private let cameraXHandle = SCNNode()
    private let defaultCameraDistance: SCNFloat = 10.0
    private let zoomedOutCameraDistance: SCNFloat = 14.0
    private let zoomOutThreshold: Float = 8.0   // start zooming out when character is this close
    private let zoomInThreshold: Float = 12.0   // fully zoomed in when character is this far
    
    // The character
    private let character = Character()
    
    // Level progression
    private var currentLevel = 1
    private static let totalLevels = 10
    
    // Path recording and replay
    private struct DirectionSnapshot: Codable {
        let elapsed: TimeInterval
        let dx: Float
        let dy: Float
        let dz: Float
        var direction: float3 { return float3(dx, dy, dz) }
        
        init(elapsed: TimeInterval, direction: float3) {
            self.elapsed = elapsed
            self.dx = direction.x
            self.dy = direction.y
            self.dz = direction.z
        }
    }
    
    private struct SavedReplay: Codable {
        let name: String
        let filename: String
        let snapshots: [DirectionSnapshot]
    }
    
    private var recordedPath = [DirectionSnapshot]()
    private var savedReplays = [SavedReplay]()
    private var levelStartTime: TimeInterval = 0
    private var isRecording = false
    private var isReplaying = false
    private var replayIndex = 0

    internal var isShowingStartScreen = true
    
    // Game states
    private var gameIsComplete = false
    private var lockCamera = false
    
    private var grassArea: SCNMaterial!
    private var waterArea: SCNMaterial!
    private var flames = [SCNNode]()
    private var enemies = [SCNNode]()

    
    // Sounds
    private var collectPearlSound: SCNAudioSource!
    private var collectFlowerSound: SCNAudioSource!
    private var flameThrowerSound: SCNAudioPlayer!
    private var victoryMusic: SCNAudioSource!
    
    // Particles
    private var confettiParticleSystem: SCNParticleSystem!
    private var collectFlowerParticleSystem: SCNParticleSystem!
    
    // For automatic camera animation
    private var currentGround: SCNNode!
    private var mainGround: SCNNode!
    private var groundToCameraPosition = [SCNNode: SCNVector3]()
    
    // Game controls
    internal var controllerDPad: GCControllerDirectionPad?
    internal var controllerStoredDirection = float2(0.0) // left/right up/down
    
    #if os(OSX)
    internal var lastMousePosition = float2(0)
    #elseif os(iOS)
    internal var padTouch: UITouch?
    internal var panningTouch: UITouch?
    #endif
    
    // MARK: Initialization
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure particle systems (only once)
        collectFlowerParticleSystem = SCNParticleSystem(named: "collect.scnp", inDirectory: nil)
        collectFlowerParticleSystem.loops = false
        confettiParticleSystem = SCNParticleSystem(named: "confetti.scnp", inDirectory: nil)
        
        setupGameControllers()
        
        // Load level 1 scene as background, then show start menu on top
        loadLevel(1)
        showStartMenu()
    }
    
    // MARK: Start Menu
    
    private func showStartMenu() {
        isShowingStartScreen = true
        savedReplays = loadSavedReplays()
        let names = savedReplays.map { $0.name }
        gameView.showStartScreen(replayNames: names)
        gameView.isPlaying = false
    }
    
    internal func showExitConfirm() {
        gameView.showExitConfirmDialog()
        gameView.isPlaying = false
    }
    
    internal func hideExitConfirm() {
        gameView.hideExitConfirmDialog()
        gameView.isPlaying = true
    }
    
    internal func exitToMainMenu() {
        gameView.hideExitConfirmDialog()
        gameView.resetForNewLevel()
        showStartMenu()
    }
    
    internal func startNewRun() {
        gameView.hideStartScreen()
        isShowingStartScreen = false
        recordedPath.removeAll()
        gameView.resetForNewLevel()
        loadLevel(1)
        gameView.isPlaying = true
    }
    
    internal func startWithReplay(_ index: Int) {
        guard index < savedReplays.count else { return }
        gameView.hideStartScreen()
        isShowingStartScreen = false
        recordedPath = savedReplays[index].snapshots
        gameView.resetForNewLevel()
        loadLevel(1)
        gameView.isPlaying = true
    }
    
    private func loadLevel(_ level: Int) {
        currentLevel = level
        gameView.currentLevel = level
        
        // Reset game state
        gameIsComplete = false
        lockCamera = false
        collectedPearlsCount = 0
        collectedFlowersCount = 0
        flames.removeAll()
        enemies.removeAll()
        grassArea = nil
        waterArea = nil
        currentGround = nil
        mainGround = nil
        groundToCameraPosition.removeAll()
        
        // Reset character
        character.reset()
        gameView.resetTimer()
        
        // Configure path recording / replay
        levelStartTime = 0
        if level == 1 && recordedPath.isEmpty {
            // New run: record the player's path
            isRecording = true
            isReplaying = false
        } else {
            // Replay mode: either loaded from file or recorded from level 1
            isRecording = false
            isReplaying = !recordedPath.isEmpty
            replayIndex = 0
        }
        
        // Load the level scene
        let scene = SCNScene(named: "game.scnassets/level\(level).scn")!
        
        // Fix deprecated animation keypaths (e.g. camera.aperture) embedded in the scene
        scene.rootNode.enumerateChildNodes { (child, _) in
            for key in child.animationKeys {
                if let animation = child.animation(forKey: key) {
                    animation.fixDeprecatedKeypaths()
                    child.addAnimation(animation, forKey: key)
                }
            }
        }
        
        self.gameView.scene = scene
        self.gameView.isPlaying = true
        self.gameView.loops = true
        
        // Various setup
        setupCamera()
        setupSounds()
        
        // Add the character to the scene (remove from previous scene tree first)
        character.node.removeFromParentNode()
        scene.rootNode.addChildNode(character.node)
        
        // Add cloud orbit to the scene root so it doesn't rotate with the character
        character.cloudOrbitNode.removeFromParentNode()
        scene.rootNode.addChildNode(character.cloudOrbitNode)
        
        let startPosition = scene.rootNode.childNode(withName: "startingPoint", recursively: true)!
        character.node.transform = startPosition.transform
        
        // Retrieve various game elements in one traversal
        var collisionNodes = [SCNNode]()
        scene.rootNode.enumerateChildNodes { (node, _) in
            switch node.name {
            case .some("flame"):
                node.physicsBody!.categoryBitMask = BitmaskEnemy
                self.flames.append(node)
                
            case .some("enemy"):
                self.enemies.append(node)
                
            case let .some(s) where s.range(of: "collision") != nil:
                collisionNodes.append(node)
                
            default:
                break
            }
        }
        
        for node in collisionNodes {
            node.isHidden = false
            setupCollisionNode(node)
        }
        
        // Setup delegates
        scene.physicsWorld.contactDelegate = self
        gameView.delegate = self
        
        setupAutomaticCameraPositions()
    }
    
    // MARK: Managing the Camera
    
    func panCamera(_ direction: float2) {
        if lockCamera {
            return
        }
        
        var directionToPan = direction
        
        #if os(iOS) || os(tvOS)
            directionToPan *= float2(1.0, -1.0)
        #endif
        
        let F = SCNFloat(0.005)
        
        // Make sure the camera handles are correctly reset (because automatic camera animations may have put the "rotation" in a weird state.
        SCNTransaction.animateWithDuration(0.0) {
            self.cameraYHandle.removeAllActions()
            self.cameraXHandle.removeAllActions()
            
            if self.cameraYHandle.rotation.y < 0 {
                self.cameraYHandle.rotation = SCNVector4(0, 1, 0, -self.cameraYHandle.rotation.w)
            }
            
            if self.cameraXHandle.rotation.x < 0 {
                self.cameraXHandle.rotation = SCNVector4(1, 0, 0, -self.cameraXHandle.rotation.w)
            }
        }
        
        // Update the camera position with some inertia.
        SCNTransaction.animateWithDuration(0.5, timingFunction: CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)) {
            self.cameraYHandle.rotation = SCNVector4(0, 1, 0, self.cameraYHandle.rotation.y * (self.cameraYHandle.rotation.w - SCNFloat(directionToPan.x) * F))
            self.cameraXHandle.rotation = SCNVector4(1, 0, 0, (max(SCNFloat(-Double.pi / 2), min(0.13, self.cameraXHandle.rotation.w + SCNFloat(directionToPan.y) * F))))
        }
    }
    
    func updateCameraWithCurrentGround(_ node: SCNNode) {
        if gameIsComplete {
            return
        }
        
        if currentGround == nil {
            currentGround = node
            return
        }
        
        // Automatically update the position of the camera when we move to another block.
        if node != currentGround {
            currentGround = node
            
            if var position = groundToCameraPosition[node] {
                if node == mainGround && character.node.position.x < 2.5 {
                    position = SCNVector3(-0.098175, 3.926991, 0.0)
                }
                
                let actionY = SCNAction.rotateTo(x: 0, y: CGFloat(position.y), z: 0, duration: 3.0, usesShortestUnitArc: true)
                actionY.timingMode = .easeInEaseOut
                
                let actionX = SCNAction.rotateTo(x: CGFloat(position.x), y: 0, z: 0, duration: 3.0, usesShortestUnitArc: true)
                actionX.timingMode = .easeInEaseOut
                
                cameraYHandle.runAction(actionY)
                cameraXHandle.runAction(actionX)
            }
        }
    }
    
    // MARK: Moving the Character
    
    private func characterDirection() -> float3 {
        let controllerDirection = self.controllerDirection()
        var direction = float3(controllerDirection.x, 0.0, controllerDirection.y)
        
        if let pov = gameView.pointOfView {
            let p1 = pov.presentation.convertPosition(SCNVector3(direction), to: nil)
            let p0 = pov.presentation.convertPosition(SCNVector3Zero, to: nil)
            direction = float3(Float(p1.x - p0.x), 0.0, Float(p1.z - p0.z))
            
            if direction.x != 0.0 || direction.z != 0.0 {
                direction = normalize(direction)
            }
        }
        
        return direction
    }
    
    // MARK: SCNSceneRendererDelegate Conformance (Game Loop)
    
    // SceneKit calls this method exactly once per frame, so long as the SCNView object (or other SCNSceneRenderer object) displaying the scene is not paused.
    // Implement this method to add game logic to the rendering loop. Any changes you make to the scene graph during this method are immediately reflected in the displayed scene.
    
    func groundTypeFromMaterial(_ material: SCNMaterial) -> GroundType {
        if material == grassArea {
            return .grass
        }
        if material == waterArea {
            return .water
        }
        else {
            return .rock
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Reset some states every frame
        replacementPosition = nil
        maxPenetrationDistance = 0
        
        // Track elapsed time for recording/replay
        if levelStartTime == 0 {
            levelStartTime = time
        }
        let elapsed = time - levelStartTime
        
        let scene = gameView.scene!
        let direction: float3
        
        if isReplaying && !recordedPath.isEmpty {
            // Replay: look up the recorded direction for the current elapsed time
            while replayIndex < recordedPath.count - 1 && recordedPath[replayIndex + 1].elapsed <= elapsed {
                replayIndex += 1
            }
            if replayIndex < recordedPath.count {
                direction = recordedPath[replayIndex].direction
            } else {
                direction = float3(0, 0, 0)
            }
        } else {
            // Live input
            direction = characterDirection()
        }
        
        // Record direction during first level
        if isRecording && !gameIsComplete {
            recordedPath.append(DirectionSnapshot(elapsed: elapsed, direction: direction))
        }
        
        // Update the on-screen timer
        if !gameIsComplete {
            gameView.updateTimer(elapsed: elapsed)
        }
        
        let groundNode = character.walkInDirection(direction, time: time, scene: scene, groundTypeFromMaterial:groundTypeFromMaterial)
        if let groundNode = groundNode {
            updateCameraWithCurrentGround(groundNode)
        }
        
        // Keep the cloud orbit centered above the character (it's in the scene root, not a child of the character)
        let charPos = character.node.position
        character.cloudOrbitNode.position = SCNVector3(charPos.x, charPos.y + character.cloudHeight, charPos.z)
        
        // Flames are static physics bodies, but they are moved by an action - So we need to tell the physics engine that the transforms did change.
        for flame in flames {
            flame.physicsBody!.resetTransform()
        }
        
        // Adjust the volume of the enemy based on the distance to the character.
        var distanceToClosestEnemy = Float.infinity
        let characterPosition = float3(character.node.position)
        for enemy in enemies {
            //distance to enemy
            let enemyTransform = float4x4(enemy.worldTransform)
            let enemyPosition = float3(enemyTransform[3].x, enemyTransform[3].y, enemyTransform[3].z)
            let distance = simd.distance(characterPosition, enemyPosition)
            distanceToClosestEnemy = min(distanceToClosestEnemy, distance)
        }
        
        // Adjust sounds volumes based on distance with the enemy.
        if !gameIsComplete {
            if let mixer = flameThrowerSound!.audioNode as? AVAudioMixerNode {
                mixer.volume = 0.3 * max(0, min(1, 1 - ((distanceToClosestEnemy - 1.2) / 1.6)))
            }
        }
        
        // Dynamic camera zoom: pull back when the character is close to the camera
        if let pov = gameView.pointOfView {
            let cameraWorldTransform = float4x4(pov.presentation.worldTransform)
            let cameraWorldPos = float3(cameraWorldTransform[3].x, cameraWorldTransform[3].y, cameraWorldTransform[3].z)
            let charPos = float3(character.node.presentation.position)
            let distToCamera = simd.distance(cameraWorldPos, charPos)
            
            // Interpolate: close → zoomed out, far → default distance
            let t = max(0, min(1, (distToCamera - zoomOutThreshold) / (zoomInThreshold - zoomOutThreshold)))
            let targetZ = SCNFloat(zoomedOutCameraDistance + (defaultCameraDistance - zoomedOutCameraDistance) * SCNFloat(t))
            
            // Smooth lerp toward the target distance
            let currentZ = pov.position.z
            pov.position.z = currentZ + (targetZ - currentZ) * 0.05
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        // If we hit a wall, position needs to be adjusted
        if let position = replacementPosition {
            character.node.position = position
        }
    }
    
    // MARK: SCNPhysicsContactDelegate Conformance
    
    // To receive contact messages, you set the contactDelegate property of an SCNPhysicsWorld object.
    // SceneKit calls your delegate methods when a contact begins, when information about the contact changes, and when the contact ends.
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        contact.match(BitmaskCollision) { (matching, other) in
            self.characterNode(other, hitWall: matching, withContact: contact)
        }
        contact.match(BitmaskCollectable) { (matching, _) in
            self.collectPearl(matching)
        }
        contact.match(BitmaskSuperCollectable) { (matching, _) in
            self.collectFlower(matching)
        }
        contact.match(BitmaskEnemy) { (_, _) in
            self.character.catchFire()
        }
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didUpdate contact: SCNPhysicsContact) {
        contact.match(BitmaskCollision) { (matching, other) in
            self.characterNode(other, hitWall: matching, withContact: contact)
        }
    }
    
    private var maxPenetrationDistance = CGFloat(0.0)
    private var replacementPosition: SCNVector3?
    
    private func characterNode(_ characterNode: SCNNode, hitWall wall: SCNNode, withContact contact: SCNPhysicsContact) {
        if characterNode.parent != character.node {
            return
        }
        
        if maxPenetrationDistance > contact.penetrationDistance {
            return
        }
        
        maxPenetrationDistance = contact.penetrationDistance
        
        var characterPosition = float3(character.node.position)
        var positionOffset = float3(contact.contactNormal) * Float(contact.penetrationDistance)
        positionOffset.y = 0
        characterPosition += positionOffset
        
        replacementPosition = SCNVector3(characterPosition)
    }
    
    // MARK: Replay Persistence
    
    private static var replaysDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Replays")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private func saveReplay(_ snapshots: [DirectionSnapshot]) {
        let now = Date()
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "replay_\(fileFmt.string(from: now)).json"
        
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMM d, yyyy h:mm a"
        let name = displayFmt.string(from: now)
        
        let replay = SavedReplay(name: name, filename: filename, snapshots: snapshots)
        if let data = try? JSONEncoder().encode(replay) {
            let url = GameViewController.replaysDirectory.appendingPathComponent(filename)
            try? data.write(to: url)
        }
    }
    
    private func loadSavedReplays() -> [SavedReplay] {
        let dir = GameViewController.replaysDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var replays = [SavedReplay]()
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let replay = try? JSONDecoder().decode(SavedReplay.self, from: data) {
                replays.append(replay)
            }
        }
        // Sort by filename (which contains the date) descending — newest first
        replays.sort { $0.filename > $1.filename }
        return replays
    }
    
    // MARK: Scene Setup
    
    private func setupCamera() {
        let ALTITUDE = 1.0
        let DISTANCE = Double(defaultCameraDistance)
        
        // We create 2 nodes to manipulate the camera:
        // The first node "cameraXHandle" is at the center of the world (0, ALTITUDE, 0) and will only rotate on the X axis
        // The second node "cameraYHandle" is a child of the first one and will ony rotate on the Y axis
        // The camera node is a child of the "cameraYHandle" at a specific distance (DISTANCE).
        // So rotating cameraYHandle and cameraXHandle will update the camera position and the camera will always look at the center of the scene.
        
        // Remove camera nodes from any previous scene tree before re-inserting
        cameraYHandle.removeFromParentNode()
        cameraXHandle.removeFromParentNode()
        
        let pov = self.gameView.pointOfView!
        pov.removeFromParentNode()
        pov.eulerAngles = SCNVector3Zero
        pov.position = SCNVector3(0.0, 0.0, DISTANCE)
        
        cameraXHandle.rotation = SCNVector4(1.0, 0.0, 0.0, -Double.pi / 4 * 0.125)
        cameraXHandle.addChildNode(pov)
        
        cameraYHandle.position = SCNVector3(0.0, ALTITUDE, 0.0)
        cameraYHandle.rotation = SCNVector4(0.0, 1.0, 0.0, Double.pi / 2 + Double.pi / 4 * 3.0)
        cameraYHandle.addChildNode(cameraXHandle)
        
        gameView.scene?.rootNode.addChildNode(cameraYHandle)
        

    }
    
    private func setupAutomaticCameraPositions() {
        let rootNode = gameView.scene!.rootNode
        
        mainGround = rootNode.childNode(withName: "bloc05_collisionMesh_02", recursively: true)
        
        groundToCameraPosition[rootNode.childNode(withName: "bloc04_collisionMesh_02", recursively: true)!] = SCNVector3(-0.188683, 4.719608, 0.0)
        groundToCameraPosition[rootNode.childNode(withName: "bloc03_collisionMesh", recursively: true)!] = SCNVector3(-0.435909, 6.297167, 0.0)
        groundToCameraPosition[rootNode.childNode(withName: "bloc07_collisionMesh", recursively: true)!] = SCNVector3( -0.333663, 7.868592, 0.0)
        groundToCameraPosition[rootNode.childNode(withName: "bloc08_collisionMesh", recursively: true)!] = SCNVector3(-0.575011, 8.739003, 0.0)
        groundToCameraPosition[rootNode.childNode(withName: "bloc06_collisionMesh", recursively: true)!] = SCNVector3( -1.095519, 9.425292, 0.0)
        groundToCameraPosition[rootNode.childNode(withName: "bloc05_collisionMesh_02", recursively: true)!] = SCNVector3(-0.072051, 8.202264, 0.0)
        groundToCameraPosition[rootNode.childNode(withName: "bloc05_collisionMesh_01", recursively: true)!] = SCNVector3(-0.072051, 8.202264, 0.0)
    }
    
    private func setupCollisionNode(_ node: SCNNode) {
        if let geometry = node.geometry {
            // Collision meshes must use a concave shape for intersection correctness.
            node.physicsBody = SCNPhysicsBody.static()
            node.physicsBody!.categoryBitMask = BitmaskCollision
            node.physicsBody!.physicsShape = SCNPhysicsShape(node: node, options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron as NSString])
            
            // Get grass area to play the right sound steps
            if geometry.firstMaterial!.name == "grass-area" {
                if grassArea != nil {
                    geometry.firstMaterial = grassArea
                } else {
                    grassArea = geometry.firstMaterial
                }
            }
            
            // Get the water area
            if geometry.firstMaterial!.name == "water" {
                waterArea = geometry.firstMaterial
            }
            
            // Temporary workaround because concave shape created from geometry instead of node fails
            let childNode = SCNNode()
            node.addChildNode(childNode)
            childNode.isHidden = true
            childNode.geometry = node.geometry
            node.geometry = nil
            node.isHidden = false
            
            if node.name == "water" {
                node.physicsBody!.categoryBitMask = BitmaskWater
            }
        }
        
        for childNode in node.childNodes {
            if childNode.isHidden == false {
                setupCollisionNode(childNode)
            }
        }
    }
    
    private func setupSounds() {
        // Get an arbitrary node to attach the sounds to.
        let node = self.gameView.scene!.rootNode
        
        node.addAudioPlayer(SCNAudioPlayer(source: SCNAudioSource(name: "music.m4a", volume: 0.25, positional: false, loops: true, shouldStream: true)))
        node.addAudioPlayer(SCNAudioPlayer(source: SCNAudioSource(name: "wind.m4a", volume: 0.3, positional: false, loops: true, shouldStream: true)))
        flameThrowerSound = SCNAudioPlayer(source: SCNAudioSource(name: "flamethrower.mp3", volume: 0, positional: false, loops: true))
        node.addAudioPlayer(flameThrowerSound)
        
        collectPearlSound = SCNAudioSource(name: "collect1.mp3", volume: 0.5)
        collectFlowerSound = SCNAudioSource(name: "collect2.mp3")
        victoryMusic = SCNAudioSource(name: "Music_victory.mp3", volume: 0.5, shouldLoad: false)
    }
    
    // MARK: Collecting Items
    
    private func removeNode(_ node: SCNNode, soundToPlay sound: SCNAudioSource) {
        if let parentNode = node.parent {
            let soundEmitter = SCNNode()
            soundEmitter.position = node.position
            parentNode.addChildNode(soundEmitter)
            
            soundEmitter.runAction(SCNAction.sequence([
                SCNAction.playAudio(sound, waitForCompletion: true),
                SCNAction.removeFromParentNode()]))
            
            node.removeFromParentNode()
        }
    }
    
    private var collectedPearlsCount = 0 {
        didSet {
            gameView.collectedPearlsCount = collectedPearlsCount
        }
    }
    
    private func collectPearl(_ pearlNode: SCNNode) {
        if pearlNode.parent != nil {
            removeNode(pearlNode, soundToPlay:collectPearlSound)
            collectedPearlsCount += 1
        }
    }
    
    private var collectedFlowersCount = 0 {
        didSet {
            gameView.collectedFlowersCount = collectedFlowersCount
            if (collectedFlowersCount == 3) {
                showEndScreen()
            }
        }
    }
    
    private func collectFlower(_ flowerNode: SCNNode) {
        if flowerNode.parent != nil {
            // Emit particles.
            var particleSystemPosition = flowerNode.worldTransform
            particleSystemPosition.m42 += 0.1
            #if os(iOS) || os(tvOS)
            gameView.scene!.addParticleSystem(collectFlowerParticleSystem, transform: particleSystemPosition)
            #elseif os(OSX)
            gameView.scene!.addParticleSystem(collectFlowerParticleSystem, transform: particleSystemPosition)
            #endif
            
            // Remove the flower from the scene.
            removeNode(flowerNode, soundToPlay:collectFlowerSound)
            collectedFlowersCount += 1
        }
    }
    
    // MARK: Congratulating the Player
    
    private func showEndScreen() {
        gameIsComplete = true
        
        // Add confettis
        let particleSystemPosition = SCNMatrix4MakeTranslation(0.0, 8.0, 0.0)
        #if os(iOS) || os(tvOS)
        gameView.scene!.addParticleSystem(confettiParticleSystem, transform: particleSystemPosition)
        #elseif os(OSX)
        gameView.scene!.addParticleSystem(confettiParticleSystem, transform: particleSystemPosition)
        #endif
        
        // Stop the music.
        gameView.scene!.rootNode.removeAllAudioPlayers()
        
        // Play the congrat sound.
        gameView.scene!.rootNode.addAudioPlayer(SCNAudioPlayer(source: victoryMusic))
        
        // Animate the camera
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.cameraYHandle.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y:-1, z: 0, duration: 3)))
            self.cameraXHandle.runAction(SCNAction.rotateTo(x: CGFloat(-Double.pi / 4), y: 0, z: 0, duration: 5.0))
        }
        
        gameView.showEndScreen()
        
        // Save replay on level 1 completion during a new run
        if currentLevel == 1 && isRecording {
            saveReplay(recordedPath)
            isRecording = false
        }
        
        // Progress to the next level after a delay, or return to start screen after last level
        if currentLevel < GameViewController.totalLevels {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                self.gameView.resetForNewLevel()
                self.loadLevel(self.currentLevel + 1)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                self.gameView.resetForNewLevel()
                self.showStartMenu()
            }
        }
    }
    
}
