/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    The view displaying the game scene, including the 2D overlay.
*/

import simd
import SceneKit
import SpriteKit
    
class GameView: SCNView {
    
    // MARK: 2D Overlay
    
    private let overlayNode = SKNode()
    private let congratulationsGroupNode = SKNode()
    private let collectedPearlCountLabel = SKLabelNode(fontNamed: "Chalkduster")
    private let levelLabel = SKLabelNode(fontNamed: "Chalkduster")
    private var collectedFlowerSprites = [SKSpriteNode]()
    private let vectorListNode = SKNode()
    private let startScreenNode = SKNode()
    var isStartScreenVisible = false
    private var startScreenItemNodes = [SKNode]()  // "New Run" + replay labels for hit testing
    
    #if os(iOS) || os(tvOS)
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setup2DOverlay()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layout2DOverlay()
    }
    
    #elseif os(OSX)
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setup2DOverlay()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layout2DOverlay()
    }
    
    #endif
    
    private func layout2DOverlay() {
        overlayNode.position = CGPoint(x: 0.0, y: bounds.size.height)
        levelLabel.position = CGPoint(x: bounds.size.width * 0.5, y: -50)
        vectorListNode.position = CGPoint(x: bounds.size.width, y: 0)
        
        congratulationsGroupNode.position = CGPoint(x: bounds.size.width * 0.5, y: bounds.size.height * 0.5)
        
        congratulationsGroupNode.xScale = 1.0
        congratulationsGroupNode.yScale = 1.0
        let currentBbox = congratulationsGroupNode.calculateAccumulatedFrame()
        
        let margin = CGFloat(25.0)
        let maximumAllowedBbox = bounds.insetBy(dx: margin, dy: margin)
        
        let top = currentBbox.maxY - congratulationsGroupNode.position.y
        let bottom = congratulationsGroupNode.position.y - currentBbox.minY
        let maxTopAllowed = maximumAllowedBbox.maxY - congratulationsGroupNode.position.y
        let maxBottomAllowed = congratulationsGroupNode.position.y - maximumAllowedBbox.minY
        
        let left = congratulationsGroupNode.position.x - currentBbox.minX
        let right = currentBbox.maxX - congratulationsGroupNode.position.x
        let maxLeftAllowed = congratulationsGroupNode.position.x - maximumAllowedBbox.minX
        let maxRightAllowed = maximumAllowedBbox.maxX - congratulationsGroupNode.position.x
        
        let topScale = top > maxTopAllowed ? maxTopAllowed / top : 1
        let bottomScale = bottom > maxBottomAllowed ? maxBottomAllowed / bottom : 1
        let leftScale = left > maxLeftAllowed ? maxLeftAllowed / left : 1
        let rightScale = right > maxRightAllowed ? maxRightAllowed / right : 1
        
        let scale = min(topScale, min(bottomScale, min(leftScale, rightScale)))
        
        congratulationsGroupNode.xScale = scale
        congratulationsGroupNode.yScale = scale
    }
    
    private func setup2DOverlay() {
        let w = bounds.size.width
        let h = bounds.size.height
        
        // Setup the game overlays using SpriteKit.
        let skScene = SKScene(size: CGSize(width: w, height: h))
        skScene.scaleMode = .resizeFill
        
        skScene.addChild(overlayNode)
        overlayNode.position = CGPoint(x: 0.0, y: h)
        
        // The Max icon.
        overlayNode.addChild(SKSpriteNode(imageNamed: "MaxIcon.png", position: CGPoint(x: 50, y: -50), scale: 0.5))
        
        // The flowers.
        for i in 0..<3 {
            collectedFlowerSprites.append(SKSpriteNode(imageNamed: "FlowerEmpty.png", position: CGPoint(x: 110 + i * 40, y: -50), scale: 0.25))
            overlayNode.addChild(collectedFlowerSprites[i])
        }
        
        // The pearl icon and count.
        overlayNode.addChild(SKSpriteNode(imageNamed: "ItemsPearl.png", position: CGPoint(x: 110, y: -100), scale: 0.5))
        collectedPearlCountLabel.text = "x0"
        collectedPearlCountLabel.position = CGPoint(x: 152, y: -113)
        overlayNode.addChild(collectedPearlCountLabel)
        
        // The level label (centered at top)
        levelLabel.text = "Level 1"
        levelLabel.fontSize = 24
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.position = CGPoint(x: w * 0.5, y: -50)
        overlayNode.addChild(levelLabel)
        
        // The virtual D-pad
        #if os(iOS)
        
        let virtualDPadBounds = virtualDPadBoundsInScene()
        let dpadSprite = SKSpriteNode(imageNamed: "dpad.png", position: virtualDPadBounds.origin, scale: 1.0)
        dpadSprite.anchorPoint = CGPoint(x: 0.0, y: 0.0)
        dpadSprite.size = virtualDPadBounds.size
        skScene.addChild(dpadSprite)
        
        #endif
        
        // The replay vector list (right side)
        vectorListNode.position = CGPoint(x: w, y: 0)
        vectorListNode.zPosition = 10
        skScene.addChild(vectorListNode)
        
        // Assign the SpriteKit overlay to the SceneKit view.
        overlaySKScene = skScene
        skScene.isUserInteractionEnabled = false
    }
    
    var currentLevel = 1 {
        didSet {
            levelLabel.text = "Level \(currentLevel)"
        }
    }
    
    // MARK: Replay Vector List
    
    private var vectorEntryCount = 0
    
    func addReplayVector(_ direction: simd_float3) {
        let label = SKLabelNode(fontNamed: "Courier")
        label.fontSize = 11
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .baseline
        label.position = CGPoint(x: -10, y: 14)
        label.alpha = 0.0
        
        let x = String(format: "%+.2f", direction.x)
        let z = String(format: "%+.2f", direction.z)
        let mag = String(format: "%.2f", simd_length(direction))
        label.text = "(\(x), \(z))  |\(mag)|"
        
        // Color by magnitude: green when moving, dim when idle
        let speed = CGFloat(simd_length(direction))
        if speed > 0.1 {
            label.fontColor = .green
        } else {
            label.fontColor = SKColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
        }
        
        vectorListNode.addChild(label)
        vectorEntryCount += 1
        
        // Animate: fade in, scroll up, fade out, remove
        let scrollDistance = bounds.size.height * 0.85
        label.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.9, duration: 0.1),
            SKAction.group([
                SKAction.moveBy(x: 0, y: scrollDistance, duration: 8.0),
                SKAction.sequence([
                    SKAction.wait(forDuration: 6.0),
                    SKAction.fadeOut(withDuration: 2.0)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
        
        // Push existing labels up
        for child in vectorListNode.children where child !== label {
            child.run(SKAction.moveBy(x: 0, y: 14, duration: 0.05))
        }
    }
    
    func clearVectorList() {
        vectorListNode.removeAllChildren()
        vectorEntryCount = 0
    }
    
    var collectedPearlsCount = 0 {
        didSet {
            if collectedPearlsCount == 10 {
                collectedPearlCountLabel.position = CGPoint(x: 158, y: collectedPearlCountLabel.position.y)
            }
            collectedPearlCountLabel.text = "x\(collectedPearlsCount)"
        }
    }
    
    var collectedFlowersCount = 0 {
        didSet {
            guard collectedFlowersCount > 0 else { return }
            collectedFlowerSprites[collectedFlowersCount - 1].texture = SKTexture(imageNamed: "FlowerFull.png")
        }
    }
    
    // MARK: Level Reset
    
    func resetForNewLevel() {
        // Remove congratulations overlay
        congratulationsGroupNode.removeAllChildren()
        congratulationsGroupNode.removeFromParent()
        
        // Reset flower sprites to empty
        for sprite in collectedFlowerSprites {
            sprite.texture = SKTexture(imageNamed: "FlowerEmpty.png")
        }
        
        // Reset pearl count
        collectedPearlsCount = 0
        collectedFlowersCount = 0
    }
    
    // MARK: Start Screen
    
    func showStartScreen(replayNames: [String]) {
        startScreenNode.removeAllChildren()
        startScreenItemNodes.removeAll()
        isStartScreenVisible = true
        
        let w = bounds.size.width
        let h = bounds.size.height
        
        // Semi-transparent background (use SKSpriteNode to avoid stencil buffer requirement)
        let bg = SKSpriteNode(color: SKColor(red: 0, green: 0, blue: 0, alpha: 0.7), size: CGSize(width: w * 2, height: h * 2))
        bg.zPosition = 0
        startScreenNode.addChild(bg)
        
        // Title
        let title = SKLabelNode(fontNamed: "Chalkduster")
        title.text = "Fox"
        title.fontSize = 60
        title.fontColor = .white
        title.position = CGPoint(x: 0, y: h * 0.3)
        title.zPosition = 1
        startScreenNode.addChild(title)
        
        // "New Run" button
        let newRunLabel = SKLabelNode(fontNamed: "Chalkduster")
        newRunLabel.text = "New Run"
        newRunLabel.fontSize = 28
        newRunLabel.fontColor = .green
        newRunLabel.name = "startItem_0"
        newRunLabel.position = CGPoint(x: 0, y: h * 0.1)
        newRunLabel.zPosition = 1
        startScreenNode.addChild(newRunLabel)
        startScreenItemNodes.append(newRunLabel)
        
        // Saved replay list
        let startY = h * 0.1 - 60
        for (i, name) in replayNames.enumerated() {
            let label = SKLabelNode(fontNamed: "Chalkduster")
            label.text = name
            label.fontSize = 20
            label.fontColor = SKColor(red: 0.8, green: 0.8, blue: 1.0, alpha: 1.0)
            label.name = "startItem_\(i + 1)"
            label.position = CGPoint(x: 0, y: startY - CGFloat(i) * 40)
            label.zPosition = 1
            startScreenNode.addChild(label)
            startScreenItemNodes.append(label)
        }
        
        startScreenNode.position = CGPoint(x: w * 0.5, y: h * 0.5)
        startScreenNode.zPosition = 100
        
        overlaySKScene?.addChild(startScreenNode)
    }
    
    func hideStartScreen() {
        startScreenNode.removeAllChildren()
        startScreenNode.removeFromParent()
        startScreenItemNodes.removeAll()
        isStartScreenVisible = false
    }
    
    /// Returns the index of the tapped start screen item (0 = New Run, 1+ = replay index), or nil
    func startScreenHitTest(at point: CGPoint) -> Int? {
        guard isStartScreenVisible, let skScene = overlaySKScene else { return nil }
        let nodesAtPoint = skScene.nodes(at: point)
        for node in nodesAtPoint {
            if let name = node.name, name.hasPrefix("startItem_"),
               let index = Int(name.replacingOccurrences(of: "startItem_", with: "")) {
                return index
            }
        }
        return nil
    }
    
    // MARK: Congratulating the Player
    
    func showEndScreen() {
        // Congratulation title
        let congratulationsNode = SKSpriteNode(imageNamed: "congratulations.png")
        
        // Max image
        let characterNode = SKSpriteNode(imageNamed: "congratulations_pandaMax.png")
        characterNode.position = CGPoint(x: 0.0, y: -220.0)
        characterNode.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        
        congratulationsGroupNode.addChild(characterNode)
        congratulationsGroupNode.addChild(congratulationsNode)
        
        let overlayScene = overlaySKScene!
        overlayScene.addChild(congratulationsGroupNode)
        
        // Layout the overlay
        layout2DOverlay()
        
        // Animate
        (congratulationsNode.alpha, congratulationsNode.xScale, congratulationsNode.yScale) = (0.0, 0.0, 0.0)
        congratulationsNode.run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.sequence([SKAction.scale(to: 1.22, duration: 0.25), SKAction.scale(to: 1.0, duration: 0.1)])]))
        
        (characterNode.alpha, characterNode.xScale, characterNode.yScale) = (0.0, 0.0, 0.0)
        characterNode.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.5),
                SKAction.sequence([SKAction.scale(to: 1.22, duration: 0.25), SKAction.scale(to: 1.0, duration: 0.1)])])]))
        
        congratulationsGroupNode.position = CGPoint(x: bounds.size.width * 0.5, y: bounds.size.height * 0.5);
    }
    
    // MARK: Mouse and Keyboard Events
    
    #if os(OSX)
   
    var eventsDelegate: KeyboardAndMouseEventsDelegate?
    
    override func mouseDown(with event: NSEvent) {
        guard let eventsDelegate = eventsDelegate, eventsDelegate.mouseDown(in: self, with: event) else {
            super.mouseDown(with: event)
            return
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let eventsDelegate = eventsDelegate, eventsDelegate.mouseDragged(in: self, with: event) else {
            super.mouseDragged(with: event)
            return
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let eventsDelegate = eventsDelegate, eventsDelegate.mouseUp(in: self, with: event) else {
            super.mouseUp(with: event)
            return
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard let eventsDelegate = eventsDelegate, eventsDelegate.keyDown(in: self, with: event) else {
            super.keyDown(with: event)
            return
        }
    }
    
    override func keyUp(with event: NSEvent) {
        guard let eventsDelegate = eventsDelegate, eventsDelegate.keyUp(in: self, with: event) else {
            super.keyUp(with: event)
            return
        }
    }
    
    #endif
    
    // MARK: Virtual D-pad
    
    #if os(iOS)
    
    private func virtualDPadBoundsInScene() -> CGRect {
        return CGRect(x: 10.0, y: 10.0, width: 150.0, height: 150.0)
    }
    
    func virtualDPadBounds() -> CGRect {
        var virtualDPadBounds = virtualDPadBoundsInScene()
        virtualDPadBounds.origin.y = bounds.size.height - virtualDPadBounds.size.height + virtualDPadBounds.origin.y
        return virtualDPadBounds
    }
    
    #endif
    
}
