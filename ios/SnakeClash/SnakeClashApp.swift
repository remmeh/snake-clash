import SwiftUI
import SpriteKit
import UIKit

private let palette: [(String, UIColor)] = [
    ("Lavender", UIColor(red: 0.68, green: 0.55, blue: 0.96, alpha: 1)),
    ("Mint", UIColor(red: 0.43, green: 0.85, blue: 0.68, alpha: 1)),
    ("Coral", UIColor(red: 1, green: 0.48, blue: 0.54, alpha: 1)),
    ("Sky", UIColor(red: 0.39, green: 0.75, blue: 1, alpha: 1)),
    ("Gold", UIColor(red: 1, green: 0.78, blue: 0.30, alpha: 1)),
    ("Lime", UIColor(red: 0.74, green: 0.91, blue: 0.38, alpha: 1))
]

@main
struct SnakeClashApp: App {
    var body: some Scene { WindowGroup { NativeGameView().preferredColorScheme(.dark) } }
}

final class GameController: ObservableObject {
    enum Mode { case ready, playing, paused, over }
    @Published var mode: Mode = .ready {
        didSet { audio.setPlaying(mode == .playing) }
    }
    @Published var soundEnabled = !UserDefaults.standard.bool(forKey: "sound-muted") {
        didSet {
            UserDefaults.standard.set(!soundEnabled, forKey: "sound-muted")
            audio.isEnabled = soundEnabled
        }
    }
    private let audio = GameAudio()

    init() {
        audio.isEnabled = soundEnabled
        if let data = UserDefaults.standard.data(forKey: "saved-round-v1"),
           world.restore(from: data) {
            mode = .paused
            score = world.score; energy = world.energy; eaten = world.eaten
            message = "Welcome back. Your snacks are waiting!"
        }
    }

    func saveProgress() {
        guard mode == .playing || mode == .paused else { return }
        if let data = world.saveData() {
            UserDefaults.standard.set(data, forKey: "saved-round-v1")
        }
        if world.score > best {
            best = world.score
            UserDefaults.standard.set(best, forKey: "native-best")
        }
    }

    func playCollectionSounds(at time: Double) {
        if !world.events.isEmpty { audio.eatSnake(at: time) }
        else if world.collectedDots > 0 { audio.collectDot(at: time) }
    }
    @Published var score = 0
    @Published var best = UserDefaults.standard.integer(forKey: "native-best")
    @Published var energy = 1.0
    @Published var eaten = 0
    @Published var leaders: [(String, Int)] = []
    @Published var message = "Drag anywhere to steer. Eat smaller snakes!"
    @Published var selectedColor = min(palette.count - 1, max(0, UserDefaults.standard.integer(forKey: "snake-color"))) {
        didSet { UserDefaults.standard.set(selectedColor, forKey: "snake-color") }
    }
    let world = GameWorld()
    var boosting = false
    lazy var scene: ArenaScene = {
        let result = ArenaScene(size: CGSize(width: 1200, height: 900))
        result.scaleMode = .resizeFill
        result.controller = self
        return result
    }()
    func start() {
        world.reset(); scene.resetControls(); score = 0; eaten = 0; energy = 1
        message = "Drag anywhere to steer. Eat smaller snakes!"; mode = .playing
        saveProgress()
    }
    func pause() {
        guard mode == .playing else { return }
        boosting = false; scene.resetControls(); mode = .paused
        saveProgress()
    }
    func resume() { guard mode == .paused else { return }; scene.resetControls(); mode = .playing }
    func refresh() {
        if score != world.score { score = world.score }
        if energy != world.energy { energy = world.energy }
        if eaten != world.eaten { eaten = world.eaten }
        let updatedLeaders = world.snakes.filter(\.alive).sorted { $0.mass > $1.mass }.prefix(4).map { ($0.name, Int($0.mass)) }
        if !leaders.elementsEqual(updatedLeaders, by: { $0.0 == $1.0 && $0.1 == $1.1 }) { leaders = updatedLeaders }
        if world.isOver && mode == .playing {
            boosting = false
            if score > best { best = score; UserDefaults.standard.set(best, forKey: "native-best") }
            UserDefaults.standard.removeObject(forKey: "saved-round-v1")
            mode = .over
            audio.playDeath()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}

struct NativeGameView: View {
    @StateObject private var game = GameController()
    @Environment(\.scenePhase) private var phase
    @State private var showHelp = false
    private let gold = Color(red: 1, green: 0.83, blue: 0.43)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: game.scene, preferredFramesPerSecond: 60)
                    .ignoresSafeArea()
                    .accessibilityLabel("Snake arena. Drag to steer your snake.")
                VStack {
                    HStack(alignment: .top) {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles").font(.title2).foregroundStyle(gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YOUR SCORE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(.white.opacity(0.5))
                                Text(game.score.formatted()).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                            }
                        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 12) {
                            HStack(spacing: 10) {
                                soundButton
                                Button { game.pause(); showHelp = true } label: { Image(systemName: "questionmark").frame(width: 44, height: 44) }
                                    .accessibilityLabel("How to play")
                                if game.mode == .playing || game.mode == .paused {
                                    Button { game.mode == .playing ? game.pause() : game.resume() } label: {
                                        Image(systemName: game.mode == .paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                                    }.accessibilityLabel(game.mode == .paused ? "Resume game" : "Pause game")
                                }
                            }.font(.system(size: 17, weight: .semibold)).background(.ultraThinMaterial, in: Capsule())
                            if geometry.size.width > 600 {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("THE BIG BITES").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(gold)
                                    ForEach(Array(game.leaders.enumerated()), id: \.offset) { index, item in
                                        HStack { Text("\(index + 1)").foregroundStyle(.white.opacity(0.35)); Text(item.0); Spacer(minLength: 24); Text("\(item.1)").monospacedDigit() }
                                            .font(.system(size: 12, weight: item.0 == "You" ? .bold : .regular, design: .rounded))
                                    }
                                }.padding(16).frame(width: 190).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        if game.mode == .playing {
                            Label(game.message, systemImage: "sparkle")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65)).padding(14)
                                .background(.ultraThinMaterial, in: Capsule()).allowsHitTesting(false)
                        }
                        Spacer(minLength: 14)
                        if game.mode == .playing {
                            VStack(spacing: 8) {
                                Image(systemName: "bolt.fill").font(.system(size: 30, weight: .bold))
                                Text("BOOST").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2)
                                GeometryReader { bar in
                                    Capsule().fill(.white.opacity(0.12))
                                    Capsule().fill(gold).frame(width: bar.size.width * game.energy)
                                }.frame(width: 72, height: 4)
                            }.foregroundStyle(gold).frame(width: 110, height: 110)
                                .background(game.boosting ? Color.white.opacity(0.18) : Color.white.opacity(0.07), in: Circle())
                                .overlay(Circle().stroke(gold.opacity(0.35), lineWidth: 1))
                                .contentShape(Circle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in game.boosting = true }.onEnded { _ in game.boosting = false })
                                .accessibilityLabel("Boost").accessibilityHint("Hold to dash. Uses energy.")
                                .accessibilityAction { game.boosting.toggle() }
                        }
                    }
                }.padding(.horizontal, geometry.size.width > 600 ? 30 : 18).padding(.top, 18).padding(.bottom, 24)
                if game.mode != .playing { menu }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onChange(of: phase) { _, value in if value != .active { game.pause() } }
        .sheet(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome to the food chain.").font(.system(size: 32, weight: .bold, design: .rounded))
                Label("Drag anywhere in the arena to steer.", systemImage: "hand.draw.fill")
                Label("Eat smaller snakes. They burst into yellow balls!", systemImage: "sparkles")
                Label("Collect the balls to grow. Avoid bigger snakes.", systemImage: "arrow.up.right")
                Label("Hold BOOST with another finger to dash.", systemImage: "bolt.fill")
                Text("Your own tail is safe. The arena wraps at the edges. Choose your snake’s color before every round.").foregroundStyle(.secondary)
                Button("Let’s play") { showHelp = false }.buttonStyle(.borderedProminent).tint(Color(palette[game.selectedColor].1))
            }.padding(36).presentationDetents([.medium, .large])
        }
    }

    private var soundButton: some View {
        Button { game.soundEnabled.toggle() } label: {
            Image(systemName: game.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .frame(width: 44, height: 44)
        }.accessibilityLabel(game.soundEnabled ? "Mute sound" : "Enable sound")
            .accessibilityHint("Ambient music and eating sounds")
    }

    private var menu: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(game.mode == .paused ? "TAKE A LITTLE BREATHER" : "SNAKE CLASH")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(4).foregroundStyle(gold)
                Image(systemName: game.mode == .over ? "crown.fill" : "scribble.variable")
                    .font(.system(size: 65, weight: .bold)).foregroundStyle(Color(palette[game.selectedColor].1))
                Text(game.mode == .paused ? "Your snacks can wait." : game.mode == .over ? "A tasty little run." : "Small snake.\nBig appetite.")
                    .font(.system(size: 38, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                Text(game.mode == .over ? "\(game.score) points · \(game.eaten) snakes eaten" : "Eat smaller snakes. Turn them into gold.\nGrow into the biggest bite in the arena.")
                    .font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center).lineSpacing(5)
                if game.mode != .paused {
                    VStack(spacing: 12) {
                        Text("PICK YOUR COLOR · \(palette[game.selectedColor].0.uppercased())")
                            .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(.white.opacity(0.6))
                        HStack(spacing: 12) {
                            ForEach(palette.indices, id: \.self) { index in
                                Button { game.selectedColor = index; UISelectionFeedbackGenerator().selectionChanged() } label: {
                                    Circle().fill(Color(palette[index].1)).frame(width: 36, height: 36)
                                        .overlay { if game.selectedColor == index { Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.black.opacity(0.65)) } }
                                        .padding(4).overlay(Circle().stroke(game.selectedColor == index ? .white : .clear, lineWidth: 2))
                                }.buttonStyle(.plain).accessibilityLabel("\(palette[index].0) snake").accessibilityAddTraits(game.selectedColor == index ? .isSelected : [])
                            }
                        }
                    }.padding(.vertical, 3)
                }
                Button { game.mode == .paused ? game.resume() : game.start() } label: {
                    HStack { Spacer(); Text(game.mode == .paused ? "Keep on snacking" : game.mode == .over ? "Play again" : "Let’s get hungry"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 17, weight: .bold, design: .rounded)).padding(18)
                        .background(Color(palette[game.selectedColor].1), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.2))
                }.buttonStyle(.plain)
                HStack(spacing: 12) {
                    soundButton
                    Text(game.soundEnabled ? "SOUND ON" : "SOUND OFF")
                        .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2)
                }.foregroundStyle(.white.opacity(0.65))
                Text("BEST: \(game.best.formatted()) POINTS").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2).foregroundStyle(.white.opacity(0.35))
            }.padding(32).frame(maxWidth: 430)
                .background(Color(red: 0.12, green: 0.15, blue: 0.22), in: RoundedRectangle(cornerRadius: 32))
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.1), lineWidth: 1)).padding(20)
        }
    }
}

final class ArenaScene: SKScene {
    weak var controller: GameController?
    private var lastTime: TimeInterval = 0
    private var hudTime = 0.0
    private var saveTime = 0.0
    private var messageUntil = 0.0
    private var heading = Double.pi / 5
    private var steeringTouch: UITouch?
    private var origin = CGPoint.zero
    private let grid = SKShapeNode()
    private let foodLayer = SKNode()
    private let snakeLayer = SKNode()
    private let effectLayer = SKNode()
    private let stick = SKShapeNode(circleOfRadius: 48)
    private let knob = SKShapeNode(circleOfRadius: 20)
    private var foodNodes: [Int: SKSpriteNode] = [:]
    // One rasterized glow is shared by every food dot and burst particle.
    private lazy var foodTexture: SKTexture = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            let cg = context.cgContext
            cg.setShadow(offset: .zero, blur: 5, color: UIColor.systemYellow.withAlphaComponent(0.65).cgColor)
            UIColor(red: 1, green: 0.82, blue: 0.40, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 8, y: 8, width: 16, height: 16))
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(red: 1, green: 0.95, blue: 0.72, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 11, y: 17, width: 5, height: 5))
        }
        return SKTexture(image: image)
    }()
    private var lastRenderColor = -1
    private var needsRender = true
    private var snakeNodes: [Int: SnakeVisual] = [:]
    private var gridSize = CGSize.zero

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.085, green: 0.11, blue: 0.17, alpha: 1)
        guard grid.parent == nil else { return }
        addChild(grid); addChild(foodLayer); addChild(snakeLayer); addChild(effectLayer)
        grid.strokeColor = UIColor.white.withAlphaComponent(0.05); grid.lineWidth = 1
        stick.fillColor = UIColor.white.withAlphaComponent(0.04); stick.strokeColor = UIColor.white.withAlphaComponent(0.2)
        knob.fillColor = UIColor.white.withAlphaComponent(0.2); knob.strokeColor = UIColor.white.withAlphaComponent(0.2)
        stick.addChild(knob); stick.zPosition = 100; stick.isHidden = true; addChild(stick)
        view.isMultipleTouchEnabled = true
    }

    func resetControls() { needsRender = true; steeringTouch = nil; stick.isHidden = true; heading = controller?.world.player.angle ?? 0; lastTime = 0 }

    private func screen(_ point: Point) -> CGPoint {
        guard let player = controller?.world.player else { return .zero }
        return CGPoint(x: size.width / 2 + GameWorld.delta(point.x, player.position.x), y: size.height / 2 + GameWorld.delta(point.y, player.position.y))
    }

    override func update(_ currentTime: TimeInterval) {
        guard let game = controller else { return }
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.04); lastTime = currentTime
        if game.mode == .playing {
            needsRender = true
            game.world.update(dt, angle: heading, boost: game.boosting)
            if !game.world.isOver && currentTime - saveTime >= 10 {
                game.saveProgress(); saveTime = currentTime
            }
            if !game.world.isOver { game.playCollectionSounds(at: currentTime) }
            if !game.world.events.isEmpty {
                for event in game.world.events { burst(at: screen(event.position)); game.message = "\(event.name) → \(event.count) yellow bites!" }
                game.world.events.removeAll(); messageUntil = currentTime + 3
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            if currentTime > messageUntil && messageUntil > 0 { game.message = "Keep growing. Bigger snakes can eat you!"; messageUntil = 0 }
        }
        if currentTime - hudTime > 0.12 { game.refresh(); hudTime = currentTime }
        if game.mode == .playing || needsRender || size != gridSize || lastRenderColor != game.selectedColor {
            render()
            needsRender = false
            lastRenderColor = game.selectedColor
        }
    }

    private func render() {
        guard let game = controller else { return }
        let world = game.world
        if size != gridSize {
            gridSize = size
            let path = CGMutablePath()
            for x in stride(from: -50.0, through: Double(size.width) + 100, by: 50) {
                for y in stride(from: -50.0, through: Double(size.height) + 100, by: 50) {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
            grid.path = path
        }
        grid.position = CGPoint(x: -world.player.position.x.truncatingRemainder(dividingBy: 50), y: -world.player.position.y.truncatingRemainder(dividingBy: 50))
        let activeFood = Set(world.food.map(\.id))
        for id in Array(foodNodes.keys) where !activeFood.contains(id) { foodNodes.removeValue(forKey: id)?.removeFromParent() }
        for bite in world.food {
            let point = screen(bite.position)
            let visible = point.x > -20 && point.x < size.width + 20 && point.y > -20 && point.y < size.height + 20
            if let node = foodNodes[bite.id] { node.position = point; node.isHidden = !visible }
            else if visible {
                let node = SKSpriteNode(texture: foodTexture)
                let diameter = bite.radius * (bite.value == 2 ? 4.8 : 4)
                node.size = CGSize(width: diameter, height: diameter)
                node.position = point; foodLayer.addChild(node); foodNodes[bite.id] = node
            }
        }
        for snake in world.snakes {
            if !snake.alive { snakeNodes.removeValue(forKey: snake.id)?.root.removeFromParent(); continue }
            let visual: SnakeVisual
            if let existing = snakeNodes[snake.id] { visual = existing }
            else { visual = SnakeVisual(); snakeNodes[snake.id] = visual; snakeLayer.addChild(visual.root) }
            let color = snake.id == 0 ? palette[game.selectedColor].1 : palette[snake.colorIndex].1
            visual.draw(snake, color: color, map: screen)
        }
    }

    private func burst(at position: CGPoint) {
        for _ in 0..<28 {
            let dot = SKSpriteNode(texture: foodTexture)
            let diameter = CGFloat.random(in: 8...20)
            dot.size = CGSize(width: diameter, height: diameter)
            dot.position = position; effectLayer.addChild(dot)
            let move = SKAction.moveBy(x: .random(in: -100...100), y: .random(in: -100...100), duration: 0.65)
            move.timingMode = .easeOut
            dot.run(.sequence([.group([move, .fadeOut(withDuration: 0.65)]), .removeFromParent()]))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard controller?.mode == .playing, steeringTouch == nil, let touch = touches.first else { return }
        steeringTouch = touch; origin = touch.location(in: self)
        stick.position = origin; knob.position = .zero; stick.isHidden = false
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = steeringTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self), dx = point.x - origin.x, dy = point.y - origin.y
        let length = hypot(dx, dy)
        if length > 5 { heading = atan2(dy, dx) }
        let factor = length > 0 ? min(length, 30) / length : 0
        knob.position = CGPoint(x: dx * factor, y: dy * factor)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = steeringTouch, touches.contains(touch) { steeringTouch = nil; stick.isHidden = true }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
}

private final class SnakeVisual {
    let root = SKNode()
    private let body = SKShapeNode()
    private let stripe = SKShapeNode()
    private let head = SKShapeNode()
    private let face = SKNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let shield = SKShapeNode()

    init() {
        root.addChild(body); root.addChild(stripe); root.addChild(head); root.addChild(face); root.addChild(label); root.addChild(shield)
        body.lineCap = .round; body.lineJoin = .round; stripe.lineCap = .round; stripe.lineJoin = .round
        label.fontSize = 11; label.fontColor = UIColor.white.withAlphaComponent(0.6)
        for side in [-1.0, 1.0] {
            let eye = SKShapeNode(circleOfRadius: 4.5); eye.fillColor = .white; eye.strokeColor = .clear
            eye.position = CGPoint(x: 5, y: side * 6)
            let pupil = SKShapeNode(circleOfRadius: 2.2); pupil.fillColor = UIColor(red: 0.1, green: 0.12, blue: 0.18, alpha: 1); pupil.strokeColor = .clear; pupil.position.x = 1.5
            eye.addChild(pupil); face.addChild(eye)
        }
        shield.fillColor = .clear; shield.strokeColor = UIColor.white.withAlphaComponent(0.3); shield.lineWidth = 1
    }
    func draw(_ snake: Snake, color: UIColor, map: (Point) -> CGPoint) {
        let path = CGMutablePath()
        let headPoint = map(snake.position)
        path.move(to: headPoint)
        var previous = headPoint
        // The trail is spaced three points apart; nine-point drawing segments
        // retain its curve while reducing per-frame path tessellation.
        for index in stride(from: 0, to: snake.trail.count, by: 3) {
            let p = map(snake.trail[index])
            if hypot(p.x - previous.x, p.y - previous.y) > 100 { path.move(to: p) } else { path.addLine(to: p) }
            previous = p
        }
        if let tail = snake.trail.last {
            let end = map(tail)
            if hypot(end.x - previous.x, end.y - previous.y) < 100 { path.addLine(to: end) }
        }
        body.path = path; body.strokeColor = color; body.lineWidth = snake.radius * 2
        stripe.path = path; stripe.strokeColor = UIColor.white.withAlphaComponent(0.13); stripe.lineWidth = snake.radius * 0.8
        head.path = CGPath(ellipseIn: CGRect(x: -snake.radius, y: -snake.radius, width: snake.radius * 2, height: snake.radius * 2), transform: nil)
        head.fillColor = color; head.strokeColor = .clear; head.position = headPoint
        face.position = headPoint; face.zRotation = snake.angle; face.setScale(snake.radius / 13)
        label.text = snake.id == 0 ? "YOU" : snake.name; label.position = CGPoint(x: headPoint.x, y: headPoint.y + snake.radius + 14)
        shield.path = CGPath(ellipseIn: CGRect(x: -snake.radius - 7, y: -snake.radius - 7, width: (snake.radius + 7) * 2, height: (snake.radius + 7) * 2), transform: nil)
        shield.position = headPoint; shield.isHidden = snake.id != 0 || snake.protection <= 0
        root.zPosition = snake.mass
    }
}
