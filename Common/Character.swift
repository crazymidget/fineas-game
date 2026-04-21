/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    This class manages the main character, including its animations, sounds and direction.
*/

import SceneKit

enum GroundType: Int {
    case grass
    case rock
    case water
    case inTheAir
    case count
}

private typealias ParticleEmitter = (node: SCNNode, particleSystem: SCNParticleSystem, birthRate: CGFloat)

class Character {
    
    // MARK: Initialization
    
    init() {
        
        // MARK: Load character from external file
        
        // The character is loaded from a .scn file and stored in an intermediate
        // node that will be used as a handle to manipulate the whole group at once
        
        let characterScene = SCNScene(named: "game.scnassets/panda.scn")!
        let characterTopLevelNode = characterScene.rootNode.childNodes[0]
        node.addChildNode(characterTopLevelNode)
        
        
        // MARK: Configure collision capsule
        
        // Collisions are handled by the physics engine. The character is approximated by
        // a capsule that is configured to collide with collectables, enemies and walls
        
        let (min, max) = node.boundingBox
        let collisionCapsuleRadius = CGFloat((max.x - min.x) * 0.4)
        let collisionCapsuleHeight = CGFloat(max.y - min.y)
        
        let characterCollisionNode = SCNNode()
        characterCollisionNode.name = "collider"
        characterCollisionNode.position = SCNVector3(0.0, collisionCapsuleHeight * 0.51, 0.0) // a bit too high so that the capsule does not hit the floor
        characterCollisionNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape:SCNPhysicsShape(geometry: SCNCapsule(capRadius: collisionCapsuleRadius, height: collisionCapsuleHeight), options:nil))
        characterCollisionNode.physicsBody!.contactTestBitMask = BitmaskSuperCollectable | BitmaskCollectable | BitmaskCollision | BitmaskEnemy
        node.addChildNode(characterCollisionNode)
        
        
        // MARK: Load particle systems
        
        // Particle systems were configured in the SceneKit Scene Editor
        // They are retrieved from the scene and their birth rate are stored for later use
        
        func particleEmitterWithName(_ name: String) -> ParticleEmitter {
            let emitter: ParticleEmitter
            emitter.node = characterTopLevelNode.childNode(withName: name, recursively:true)!
            emitter.particleSystem = emitter.node.particleSystems![0]
            emitter.birthRate = emitter.particleSystem.birthRate
            emitter.particleSystem.birthRate = 0
            emitter.node.isHidden = false
            return emitter
        }
        
        fireEmitter = particleEmitterWithName("fire")
        smokeEmitter = particleEmitterWithName("smoke")
        whiteSmokeEmitter = particleEmitterWithName("whiteSmoke")
        
        
        // MARK: Load sound effects
        
        reliefSound = SCNAudioSource(name: "aah_extinction.mp3", volume: 2.0)
        haltFireSound = SCNAudioSource(name: "fire_extinction.mp3", volume: 2.0)
        catchFireSound = SCNAudioSource(name: "ouch_firehit.mp3", volume: 2.0)
        
        for i in 0..<10 {
            if let grassSound = SCNAudioSource(named: "game.scnassets/sounds/Step_grass_0\(i).mp3") {
                grassSound.volume = 0.5
                grassSound.load()
                steps[GroundType.grass.rawValue].append(grassSound)
            }
            
            if let rockSound = SCNAudioSource(named: "game.scnassets/sounds/Step_rock_0\(i).mp3") {
                rockSound.load()
                steps[GroundType.rock.rawValue].append(rockSound)
            }
            
            if let waterSound = SCNAudioSource(named: "game.scnassets/sounds/Step_splash_0\(i).mp3") {
                waterSound.load()
                steps[GroundType.water.rawValue].append(waterSound)
            }
        }
        
        
        // MARK: Configure animations
        
        // Some animations are already there and can be retrieved from the scene
        // The "walk" animation is loaded from a file, it is configured to play foot steps at specific times during the animation
        
        characterTopLevelNode.enumerateChildNodes { (child, _) in
            for key in child.animationKeys {                  // for every animation key
                let animation = child.animation(forKey: key)! // get the animation
                animation.usesSceneTimeBase = false           // make it system time based
                animation.repeatCount = Float.infinity        // make it repeat forever
                animation.fixDeprecatedKeypaths()             // fix deprecated keypaths (e.g. camera.xFov)
                child.addAnimation(animation, forKey: key)             // animations are copied upon addition, so we have to replace the previous animation
            }
        }
        
        walkAnimation = CAAnimation.animationWithSceneNamed("game.scnassets/walk.scn")
        walkAnimation.usesSceneTimeBase = false
        walkAnimation.fadeInDuration = 0.3
        walkAnimation.fadeOutDuration = 0.3
        walkAnimation.repeatCount = Float.infinity
        walkAnimation.speed = Character.speedFactor
        walkAnimation.animationEvents = [
            SCNAnimationEvent(keyTime: 0.1) { (_, _, _) in self.playFootStep() },
            SCNAnimationEvent(keyTime: 0.6) { (_, _, _) in self.playFootStep() }]
        
        
        // MARK: Create floating cloud that circles above the character
        
        cloudOrbitNode = SCNNode()
        cloudHeight = SCNFloat(collisionCapsuleHeight * 6.0)
        
        let cloudMaterial = SCNMaterial()
        cloudMaterial.lightingModel = .constant
        cloudMaterial.transparent.contents = 0.45 as NSNumber
        #if os(iOS) || os(tvOS)
        cloudMaterial.diffuse.contents = UIColor(white: 0.7, alpha: 1.0)
        #elseif os(OSX)
        cloudMaterial.diffuse.contents = NSColor(white: 0.7, alpha: 1.0)
        #endif
        cloudMaterial.writesToDepthBuffer = false
        cloudMaterial.readsFromDepthBuffer = true
        
        let puffRadius = collisionCapsuleRadius * 2.0
        let orbitRadius = collisionCapsuleRadius * 2.5
        
        func makeCloudPuff(radius: CGFloat, position: SCNVector3) -> SCNNode {
            let puff = SCNNode(geometry: SCNSphere(radius: radius))
            puff.geometry?.firstMaterial = cloudMaterial
            puff.position = position
            puff.castsShadow = false
            return puff
        }
        
        func makeCloud(scale: CGFloat) -> SCNNode {
            let cloud = SCNNode()
            let r = puffRadius * scale
            cloud.addChildNode(makeCloudPuff(radius: r, position: SCNVector3(0, 0, 0)))
            cloud.addChildNode(makeCloudPuff(radius: r * 0.75, position: SCNVector3(r * 0.8, r * 0.15, 0)))
            cloud.addChildNode(makeCloudPuff(radius: r * 0.75, position: SCNVector3(-r * 0.8, r * 0.15, 0)))
            cloud.addChildNode(makeCloudPuff(radius: r * 0.6, position: SCNVector3(0, r * 0.1, r * 0.5)))
            cloud.addChildNode(makeCloudPuff(radius: r * 0.6, position: SCNVector3(0, r * 0.1, -r * 0.5)))
            return cloud
        }
        
        // Main cloud (cloud 1)
        cloudNode = makeCloud(scale: 1.0)
        
        // Cloud 2 — slightly smaller, offset to the side and higher
        let cloud2 = makeCloud(scale: 0.7)
        cloud2.position = SCNVector3(puffRadius * 1.8, puffRadius * 0.3, puffRadius * 0.6)
        cloudNode.addChildNode(cloud2)
        
        // Cloud 3 — smaller still, offset opposite side
        let cloud3 = makeCloud(scale: 0.55)
        cloud3.position = SCNVector3(-puffRadius * 1.5, puffRadius * 0.15, -puffRadius * 0.8)
        cloudNode.addChildNode(cloud3)
        
        // Position within orbit
        cloudNode.position = SCNVector3(orbitRadius, 0, 0)
        cloudOrbitNode.addChildNode(cloudNode)
        
        // Slow primary orbit
        cloudOrbitNode.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 20.0)
        ))
        
        // Gentle bobbing on the main cloud group
        cloudNode.runAction(SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: puffRadius * 0.4, z: 0, duration: 2.5),
                SCNAction.moveBy(x: 0, y: -puffRadius * 0.4, z: 0, duration: 2.5)
            ])
        ))
        
        // Independent subtle bob on cloud 2 and 3
        cloud2.runAction(SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: puffRadius * 0.2, z: 0, duration: 3.0),
                SCNAction.moveBy(x: 0, y: -puffRadius * 0.2, z: 0, duration: 3.0)
            ])
        ))
        cloud3.runAction(SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: puffRadius * 0.15, z: 0, duration: 2.0),
                SCNAction.moveBy(x: 0, y: -puffRadius * 0.15, z: 0, duration: 2.0)
            ])
        ))
        
        // Secondary drift
        let driftNode = SCNNode()
        cloudNode.removeFromParentNode()
        driftNode.addChildNode(cloudNode)
        cloudOrbitNode.addChildNode(driftNode)
        
        driftNode.runAction(SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.moveBy(x: orbitRadius * 0.6, y: 0, z: orbitRadius * 0.3, duration: 7.0),
                SCNAction.moveBy(x: -orbitRadius * 0.4, y: 0, z: orbitRadius * 0.4, duration: 5.0),
                SCNAction.moveBy(x: -orbitRadius * 0.5, y: 0, z: -orbitRadius * 0.5, duration: 6.0),
                SCNAction.moveBy(x: orbitRadius * 0.3, y: 0, z: -orbitRadius * 0.2, duration: 4.0)
            ])
        ))
        
        // Add rain to each cloud
        func addRain(to cloud: SCNNode, scale: CGFloat) {
            let r = puffRadius * scale
            let rainNode = SCNNode()
            rainNode.position = SCNVector3(0, -r * 0.5, 0)
            cloud.addChildNode(rainNode)
            
            let rain = SCNParticleSystem()
            rain.birthRate = CGFloat(20) * scale * scale // scale area-proportionally
            rain.particleLifeSpan = 3.0
            rain.particleLifeSpanVariation = 0.5
            rain.emittingDirection = SCNVector3(0, -1, 0)
            rain.spreadingAngle = 5
            rain.particleVelocity = 0
            rain.particleVelocityVariation = 0
            rain.acceleration = SCNVector3(0, CGFloat(-collisionCapsuleHeight * 3.0), 0)
            rain.particleSize = 0.005
            rain.particleSizeVariation = 0.002
            rain.stretchFactor = 0.25
            #if os(iOS) || os(tvOS)
            rain.particleColor = UIColor(red: 0.5, green: 0.55, blue: 0.7, alpha: 0.5)
            #elseif os(OSX)
            rain.particleColor = NSColor(red: 0.5, green: 0.55, blue: 0.7, alpha: 0.5)
            #endif
            rain.particleColorVariation = SCNVector4(0.05, 0.05, 0.1, 0.1)
            rain.blendMode = .alpha
            rain.isLightingEnabled = false
            rain.isAffectedByGravity = false
            rain.emitterShape = SCNBox(width: r * 1.5, height: 0.001, length: r, chamferRadius: 0)
            
            rainNode.addParticleSystem(rain)
        }
        
        addRain(to: cloudNode, scale: 1.0)
        addRain(to: cloud2, scale: 0.7)
        addRain(to: cloud3, scale: 0.55)
        
        // Add lightning flashes to the cloud
        let lightningNode = SCNNode()
        lightningNode.position = SCNVector3(0, -puffRadius * 0.3, 0)
        cloudNode.addChildNode(lightningNode)
        
        let lightningLight = SCNLight()
        lightningLight.type = .omni
        lightningLight.attenuationStartDistance = 0
        lightningLight.attenuationEndDistance = 4
        #if os(iOS) || os(tvOS)
        let lightningOff = UIColor.black
        let lightningDim = UIColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 1.0)
        let lightningBright = UIColor(red: 1.5, green: 1.2, blue: 0.6, alpha: 1.0)
        #elseif os(OSX)
        let lightningOff = NSColor.black
        let lightningDim = NSColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 1.0)
        let lightningBright = NSColor(red: 1.5, green: 1.2, blue: 0.6, alpha: 1.0)
        #endif
        lightningLight.color = lightningOff
        lightningNode.light = lightningLight
        
        // Repeating flash pattern: quick double-flash then a long pause
        lightningNode.runAction(SCNAction.repeatForever(
            SCNAction.sequence([
                SCNAction.wait(duration: 3.0, withRange: 4.0),
                SCNAction.customAction(duration: 0.05) { node, _ in node.light?.color = lightningDim },
                SCNAction.customAction(duration: 0.05) { node, _ in node.light?.color = lightningOff },
                SCNAction.wait(duration: 0.1),
                SCNAction.customAction(duration: 0.05) { node, _ in node.light?.color = lightningBright },
                SCNAction.customAction(duration: 0.08) { node, _ in node.light?.color = lightningDim },
                SCNAction.customAction(duration: 0.05) { node, _ in node.light?.color = lightningOff },
            ])
        ))
    }
    
    // MARK: Retrieving nodes
    
    let node = SCNNode()
    private(set) var cloudNode: SCNNode!
    private(set) var cloudOrbitNode: SCNNode!
    private(set) var cloudHeight: SCNFloat = 0
    
    // MARK: Resetting the character
    
    func reset() {
        // Stop fire effects
        if isBurning {
            isBurning = false
            fireEmitter.particleSystem.birthRate = 0
            smokeEmitter.particleSystem.birthRate = 0
            whiteSmokeEmitter.particleSystem.birthRate = 0
        }
        isInvincible = false
        node.removeAllActions()
        node.opacity = 1.0
        
        // Reset movement state
        isWalking = false
        walkSpeed = 1.0
        previousUpdateTime = 0.0
        accelerationY = 0.0
        groundType = .inTheAir
    }
    
    // MARK: Controlling the character
    
    static let speedFactor = Float(1.538)
    
    private var groundType = GroundType.inTheAir
    private var previousUpdateTime = TimeInterval(0.0)
    private var accelerationY = SCNFloat(0.0) // Simulate gravity
    
    private var directionAngle: SCNFloat = 0.0 {
        didSet {
            if directionAngle != oldValue {
                node.runAction(SCNAction.rotateTo(x: 0.0, y: CGFloat(directionAngle), z: 0.0, duration: 0.1, usesShortestUnitArc: true))
            }
        }
    }
    
    func walkInDirection(_ direction: float3, time: TimeInterval, scene: SCNScene, groundTypeFromMaterial: (SCNMaterial) -> GroundType) -> SCNNode? {
        // delta time since last update
        if previousUpdateTime == 0.0 {
            previousUpdateTime = time
        }
        
        let deltaTime = Float(min(time - previousUpdateTime, 1.0 / 60.0))
        let characterSpeed = deltaTime * Character.speedFactor * 0.84
        previousUpdateTime = time
        
        let initialPosition = node.position
        
        // move
        if direction.x != 0.0 && direction.z != 0.0 {
            // move character
            let position = float3(node.position)
            node.position = SCNVector3(position + direction * characterSpeed)
            
            // update orientation
            directionAngle = SCNFloat(atan2(direction.x, direction.z))
            
            isWalking = true
        }
        else {
            isWalking = false
        }
        
        // Update the altitude of the character
        
        var position = node.position
        var p0 = position
        var p1 = position
        
        let maxRise = SCNFloat(0.08)
        let maxJump = SCNFloat(10.0)
        p0.y -= maxJump
        p1.y += maxRise
        
        // Do a vertical ray intersection
        var groundNode: SCNNode?
        let results = scene.physicsWorld.rayTestWithSegment(from: p1, to: p0, options:[.collisionBitMask: BitmaskCollision | BitmaskWater, .searchMode: SCNPhysicsWorld.TestSearchMode.closest])
        
        if let result = results.first {
            var groundAltitude = result.worldCoordinates.y
            groundNode = result.node
            
            let groundMaterial = result.node.childNodes[0].geometry!.firstMaterial!
            groundType = groundTypeFromMaterial(groundMaterial)
            
            if groundType == .water {
                if isBurning {
                    haltFire()
                }
                
                // do a new ray test without the water to get the altitude of the ground (under the water).
                let results = scene.physicsWorld.rayTestWithSegment(from: p1, to: p0, options:[.collisionBitMask: BitmaskCollision, .searchMode: SCNPhysicsWorld.TestSearchMode.closest])
                
                let result = results[0]
                groundAltitude = result.worldCoordinates.y
            }
            
            let threshold = SCNFloat(1e-5)
            let gravityAcceleration = SCNFloat(0.18)
            
            if groundAltitude < position.y - threshold {
                accelerationY += SCNFloat(deltaTime) * gravityAcceleration // approximation of acceleration for a delta time.
                if groundAltitude < position.y - 0.2 {
                    groundType = .inTheAir
                }
            }
            else {
                accelerationY = 0
            }
            
            position.y -= accelerationY
            
            // reset acceleration if we touch the ground
            if groundAltitude > position.y {
                accelerationY = 0
                position.y = groundAltitude
            }
            
            // Finally, update the position of the character.
            node.position = position
            
        }
        else {
            // no result, we are probably out the bounds of the level -> revert the position of the character.
            node.position = initialPosition
        }
        
        return groundNode
    }
    
    // MARK: Animating the character
    
    private var walkAnimation: CAAnimation!
    
    private var isWalking: Bool = false {
        didSet {
            if oldValue != isWalking {
                // Update node animation.
                if isWalking {
                    node.addAnimation(walkAnimation, forKey: "walk")
                } else {
                    node.removeAnimation(forKey: "walk", fadeOutDuration: 0.2)
                }
            }
        }
    }
    
    private var walkSpeed: Float = 1.0 {
        didSet {
            // remove current walk animation if any.
            let wasWalking = isWalking
            if wasWalking {
                isWalking = false
            }

            walkAnimation.speed = Character.speedFactor * walkSpeed
            
            // restore walk animation if needed.
            isWalking = wasWalking
        }
    }
    
    // MARK: Dealing with fire
    
    private var isBurning = false
    private var isInvincible = false
    
    private var fireEmitter: ParticleEmitter! = nil
    private var smokeEmitter: ParticleEmitter! = nil
    private var whiteSmokeEmitter: ParticleEmitter! = nil
    
    func catchFire() {
        if isInvincible == false {
            isInvincible = true
            node.runAction(SCNAction.sequence([
                SCNAction.playAudio(catchFireSound, waitForCompletion: false),
                SCNAction.repeat(SCNAction.sequence([
                    SCNAction.fadeOpacity(to: 0.01, duration: 0.1),
                    SCNAction.fadeOpacity(to: 1.0, duration: 0.1)
                    ]), count: 7),
                SCNAction.run { _ in self.isInvincible = false } ]))
        }
        
        isBurning = true
        
        // start fire + smoke
        fireEmitter.particleSystem.birthRate = fireEmitter.birthRate
        smokeEmitter.particleSystem.birthRate = smokeEmitter.birthRate
        
        // walk faster
        walkSpeed = 2.3
    }
    
    func haltFire() {
        if isBurning {
            isBurning = false
            
            node.runAction(SCNAction.sequence([
                SCNAction.playAudio(haltFireSound, waitForCompletion: true),
                SCNAction.playAudio(reliefSound, waitForCompletion: false)])
            )
            
            // stop fire and smoke
            fireEmitter.particleSystem.birthRate = 0
            SCNTransaction.animateWithDuration(1.0) {
                self.smokeEmitter.particleSystem.birthRate = 0
            }
            
            // start white smoke
            whiteSmokeEmitter.particleSystem.birthRate = whiteSmokeEmitter.birthRate
            
            // progressively stop white smoke
            SCNTransaction.animateWithDuration(5.0) {
                self.whiteSmokeEmitter.particleSystem.birthRate = 0
            }
            
            // walk normally
            walkSpeed = 1.0
        }
    }
    
    // MARK: Dealing with sound
    
    private var reliefSound: SCNAudioSource
    private var haltFireSound: SCNAudioSource
    private var catchFireSound: SCNAudioSource
    
    private var steps = [[SCNAudioSource]](repeating: [], count: GroundType.count.rawValue)
    
    private func playFootStep() {
        if groundType != .inTheAir { // We are in the air, no sound to play.
            // Play a random step sound.
            let soundsCount = steps[groundType.rawValue].count
            let stepSoundIndex = Int(arc4random_uniform(UInt32(soundsCount)))
            node.runAction(SCNAction.playAudio(steps[groundType.rawValue][stepSoundIndex], waitForCompletion: false))
        }
    }
    
}
