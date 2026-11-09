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
    var body: some Scene { WindowGroup { StartupView().preferredColorScheme(.dark) } }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            Color(red: 0.085, green: 0.11, blue: 0.17).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "scribble.variable").font(.system(size: 68, weight: .bold)).foregroundStyle(.purple)
                Text("SNAKE CLASH").font(.system(size: 26, weight: .bold, design: .rounded)).tracking(4)
                ProgressView().tint(.white).controlSize(.large)
                Text("Getting your arena ready…").foregroundStyle(.secondary)
            }
        }.statusBarHidden(true)
    }
}

private final class StartupLoader: ObservableObject {
    @Published var game: GameController?
    private var started = false
    func load() {
        guard !started else { return }
        started = true
        let loadingDeadline = ProcessInfo.processInfo.systemUptime + 0.8
        DispatchQueue.global(qos: .userInitiated).async {
            let world = GameWorld()
            let restored = UserDefaults.standard.data(forKey: "saved-round-v1").map { world.restore(from: $0) } ?? false
            DispatchQueue.main.async {
                self.game = GameController(world: world, restored: restored, loadingDeadline: loadingDeadline)
            }
        }
    }
}

private struct StartupView: View {
    @StateObject private var loader = StartupLoader()
    var body: some View {
        ZStack {
            if let game = loader.game {
                NativeGameView(game: game)

            } else { LoadingView() }
        }.onAppear { loader.load() }
    }
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

    private let loadingDeadline: TimeInterval
    private var startupCompletionScheduled = false

    init(world: GameWorld, restored: Bool, loadingDeadline: TimeInterval) {
        self.loadingDeadline = loadingDeadline
        self.world = world
        audio.isEnabled = soundEnabled
        if restored {
            mode = .paused
            score = world.score; energy = world.energy; eaten = world.eaten
            message = "Welcome back. Your snacks are waiting!"
        }
    }

    func finishStartup() {
        guard !startupCompletionScheduled else { return }
        startupCompletionScheduled = true
        let remaining = max(0, loadingDeadline - ProcessInfo.processInfo.systemUptime)
        // Keep a quick launch readable without delaying any initialization work.
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            self?.sceneReady = true
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

    func playPowerSounds(at time: Double) {
        let sounds = world.powerSounds
        world.powerSounds.removeAll()
        guard !world.isOver else { return }
        // A shield break takes priority if pickup and collision happen together.
        if let sound = sounds.last { audio.playPower(sound, at: time) }
    }

    func playCollectionSounds(at time: Double) {
        if !world.events.isEmpty { audio.eatSnake(at: time) }
        else if world.collectedDots > 0 { audio.collectDot(at: time) }
    }
    @Published var powerStatus = ""
    @Published var score = 0
    @Published var best = UserDefaults.standard.integer(forKey: "native-best")
    @Published var energy = 1.0
    @Published var eaten = 0
    @Published var leaders: [(String, Int)] = []
    @Published var message = "Drag anywhere to steer. Eat smaller snakes!"
    @Published var selectedColor = min(palette.count - 1, max(0, UserDefaults.standard.integer(forKey: "snake-color"))) {
        didSet { UserDefaults.standard.set(selectedColor, forKey: "snake-color") }
    }
    let world: GameWorld
    @Published var sceneReady = false
    var boosting = false
    lazy var scene: ArenaScene = {
        let result = ArenaScene(size: CGSize(width: 1200, height: 900))
        result.scaleMode = .resizeFill
        result.controller = self
        return result
    }()
    func start() {
        boosting = false
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
        let status = world.player.power.map { "\($0.kind.symbol) \($0.kind.title) · \(Int(ceil($0.remaining)))s" } ?? ""
        let slow = (world.player.slowedFor ?? 0) > 0 ? " ❄ SLOWED" : ""
        if powerStatus != status + slow { powerStatus = status + slow }
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
    @ObservedObject var game: GameController
    @Environment(\.scenePhase) private var phase
    @State private var showHelp = false
    @State private var confirmNewGame = false
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
                                if !game.powerStatus.isEmpty {
                                    Text(game.powerStatus).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(gold)
                                }
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
                if !game.sceneReady { LoadingView() }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onChange(of: phase) { _, value in if value != .active { game.pause() } }
        .alert("Start a new game?", isPresented: $confirmNewGame) {
            Button("Cancel", role: .cancel) {}
            Button("New Game", role: .destructive) { game.start() }
        } message: {
            Text("This replaces your current saved round. Your best score, color, and sound settings will stay.")
        }
        .sheet(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome to the food chain.").font(.system(size: 32, weight: .bold, design: .rounded))
                Label("Drag anywhere in the arena to steer.", systemImage: "hand.draw.fill")
                Label("Eat smaller snakes. They burst into yellow balls!", systemImage: "sparkles")
                Label("Collect the balls to grow. Avoid bigger snakes.", systemImage: "arrow.up.right")
                Label("Hold BOOST with another finger to dash.", systemImage: "bolt.fill")
                Text("Floating power-ups last 3–10 seconds. One at a time, then a 4-second cooldown. Ghost hides you from rivals, but collisions still count.")
                Text("⚡ Dash · 🎈 Double size · 🧲 Magnet · 🛡 Shield · 🌀 Quick Turn · ✨ Extra growth · ❄ Slow nearby rivals")
                    .font(.callout).foregroundStyle(.secondary)
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
                    HStack { Spacer(); Text(game.mode == .paused ? "Keep on snacking" : "New Game"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 17, weight: .bold, design: .rounded)).padding(18)
                        .background(Color(palette[game.selectedColor].1), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.2))
                }.buttonStyle(.plain)
                if game.mode == .paused {
                    Button { confirmNewGame = true } label: {
                        Label("New Game", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                        .accessibilityHint("Replaces the current round with a fresh game. Keeps your best score.")
                }
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
    private let pickupLayer = SKNode()
    private var pickupNodes: [UUID: SKNode] = [:]
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
        addChild(grid); addChild(foodLayer); addChild(pickupLayer); addChild(snakeLayer); addChild(effectLayer)
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
            game.playPowerSounds(at: currentTime)
            if !game.world.isOver { game.playCollectionSounds(at: currentTime) }
            if let message = game.world.powerMessage {
                game.message = message; game.world.powerMessage = nil
                messageUntil = currentTime + 3
                UISelectionFeedbackGenerator().selectionChanged()
            }
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
            if !game.sceneReady {
                game.finishStartup()
            }
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
        let activePickups = Set(world.pickups.map(\.id))
        for id in Array(pickupNodes.keys) where !activePickups.contains(id) {
            pickupNodes.removeValue(forKey: id)?.removeFromParent()
        }
        for pickup in world.pickups {
            let node: SKNode
            if let existing = pickupNodes[pickup.id] { node = existing }
            else {
                node = SKNode()
                let ring = SKShapeNode(circleOfRadius: 19)
                ring.fillColor = UIColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 0.95)
                ring.strokeColor = .systemCyan; ring.lineWidth = 2; ring.glowWidth = 3
                node.addChild(ring)
                let symbol = SKLabelNode(text: pickup.kind.symbol)
                symbol.fontSize = 23; symbol.verticalAlignmentMode = .center
                node.addChild(symbol)
                let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
                title.text = pickup.kind.title; title.fontSize = 10
                title.fontColor = .systemCyan; title.position.y = 28; node.addChild(title)
                pickupLayer.addChild(node); pickupNodes[pickup.id] = node
            }
            node.position = screen(pickup.position)
            node.setScale(1 + sin(world.time * 2) * 0.06)
            node.alpha = pickup.lifetime < 5 ? 0.55 + 0.45 * abs(sin(world.time * 4)) : 1
        }
        for snake in world.snakes {
            if !snake.alive { snakeNodes.removeValue(forKey: snake.id)?.root.removeFromParent(); continue }
            let visual: SnakeVisual
            if let existing = snakeNodes[snake.id] { visual = existing }
            else { visual = SnakeVisual(); snakeNodes[snake.id] = visual; snakeLayer.addChild(visual.root) }
            let color = snake.id == 0 ? palette[game.selectedColor].1 : palette[snake.colorIndex].1
            visual.draw(snake, color: color, dangerous: snake.id != 0 && snake.effectiveMass > world.player.effectiveMass * 1.08, map: screen)
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
    private let body = SKNode()
    private let glowLayer = SKNode()
    private var glowSegments: [SKSpriteNode] = []
    private let dangerLayer = SKNode()
    private var dangerSegments: [SKSpriteNode] = []
    private var segments: [SKSpriteNode] = []
    private let head = SKSpriteNode()
    private static var textures: [UIColor: SKTexture] = [:]
    private static var glowTextures: [UIColor: SKTexture] = [:]

    private static func glowTexture(for color: UIColor) -> SKTexture {
        if let cached = glowTextures[color] { return cached }
        // Rasterize once per color; no per-frame blur or self-intersecting paths.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            let colors = [color.withAlphaComponent(0.18).cgColor,
                          color.withAlphaComponent(0.12).cgColor,
                          color.withAlphaComponent(0.04).cgColor,
                          color.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 0.55, 0.78, 1])!
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 48, y: 48),
                startRadius: 0, endCenter: CGPoint(x: 48, y: 48), endRadius: 48, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        glowTextures[color] = texture
        return texture
    }

    private static func texture(for color: UIColor) -> SKTexture {
        if let cached = textures[color] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 60, height: 60))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        textures[color] = texture
        return texture
    }
    private let face = SKNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let shield = SKShapeNode()

    init() {
        glowLayer.zPosition = -2; root.addChild(glowLayer)
        dangerLayer.zPosition = -1; root.addChild(dangerLayer)
        root.addChild(body); root.addChild(head); root.addChild(face); root.addChild(label); root.addChild(shield)
        head.zPosition = 1; face.zPosition = 2; label.zPosition = 3; shield.zPosition = 3
        label.fontSize = 11; label.fontColor = UIColor.white.withAlphaComponent(0.6)
        for side in [-1.0, 1.0] {
            let eye = SKShapeNode(circleOfRadius: 4.5); eye.fillColor = .white; eye.strokeColor = .clear
            eye.position = CGPoint(x: 5, y: side * 6)
            let pupil = SKShapeNode(circleOfRadius: 2.2); pupil.fillColor = UIColor(red: 0.1, green: 0.12, blue: 0.18, alpha: 1); pupil.strokeColor = .clear; pupil.position.x = 1.5
            eye.addChild(pupil); face.addChild(eye)
        }
        shield.fillColor = .clear; shield.strokeColor = UIColor.white.withAlphaComponent(0.3); shield.lineWidth = 1
    }
    func draw(_ snake: Snake, color: UIColor, dangerous: Bool, map: (Point) -> CGPoint) {
        let headPoint = map(snake.position)
        root.alpha = snake.power?.kind == .ghost ? 0.35 : 1
        let texture = Self.texture(for: color)
        // Overlapping opaque discs form the body without triangulating a thick,
        // self-intersecting stroke. Tight turns and world seams cannot create spikes.
        let spacing = max(1, min(3, Int(snake.radius / 6)))
        var indices = Array(stride(from: 0, to: snake.trail.count, by: spacing))
        if let last = snake.trail.indices.last, indices.last != last { indices.append(last) }
        while segments.count < indices.count {
            let segment = SKSpriteNode(texture: texture)
            body.addChild(segment)
            segments.append(segment)
        }
        for index in segments.indices {
            let segment = segments[index]
            segment.isHidden = index >= indices.count
            guard index < indices.count else { continue }
            segment.texture = texture
            segment.position = map(snake.trail[indices[index]])
            // The 2-pixel transparent border keeps antialiasing inside the texture.
            let diameter = snake.radius * 2 * 64 / 60
            segment.size = CGSize(width: diameter, height: diameter)
        }
        // Sample the halo more sparsely than the opaque body to bound overdraw.
        var glowPositions = stride(from: 0, to: indices.count, by: 2).map { segments[$0].position }
        if let tail = snake.trail.last { glowPositions.append(map(tail)) }
        glowPositions.append(headPoint)
        let halo = Self.glowTexture(for: color)
        while glowSegments.count < glowPositions.count {
            let glow = SKSpriteNode(texture: halo)
            glowLayer.addChild(glow); glowSegments.append(glow)
        }
        for index in glowSegments.indices {
            let glow = glowSegments[index]
            glow.isHidden = index >= glowPositions.count
            guard index < glowPositions.count else { continue }
            glow.texture = halo
            glow.position = glowPositions[index]
            let diameter = (snake.radius + 10) * 2
            glow.size = CGSize(width: diameter, height: diameter)
        }
        dangerLayer.isHidden = !dangerous
        if dangerous {
            let red = Self.texture(for: UIColor(red: 1, green: 0.25, blue: 0.28, alpha: 1))
            while dangerSegments.count < indices.count + 1 {
                let outline = SKSpriteNode(texture: red)
                dangerLayer.addChild(outline); dangerSegments.append(outline)
            }
            for index in dangerSegments.indices {
                let outline = dangerSegments[index]
                outline.isHidden = index > indices.count
                guard index <= indices.count else { continue }
                outline.position = index == indices.count ? headPoint : segments[index].position
                let diameter = (snake.radius + 4) * 2 * 64 / 60
                outline.size = CGSize(width: diameter, height: diameter)
                outline.alpha = 0.85
            }
        }
        head.texture = texture
        let diameter = snake.radius * 2 * 64 / 60
        head.size = CGSize(width: diameter, height: diameter)
        head.position = headPoint
        face.position = headPoint; face.zRotation = snake.angle; face.setScale(snake.radius / 13)
        label.fontColor = dangerous ? .systemRed : UIColor.white.withAlphaComponent(0.6)
        let effect = snake.power.map { " \($0.kind.symbol) \(Int(ceil($0.remaining)))s" } ?? ""
        let slow = (snake.slowedFor ?? 0) > 0 ? " ❄" : ""
        label.text = (snake.id == 0 ? "YOU" : snake.name + (dangerous ? " · BIGGER" : "")) + effect + slow; label.position = CGPoint(x: headPoint.x, y: headPoint.y + snake.radius + 14)
        shield.path = CGPath(ellipseIn: CGRect(x: -snake.radius - 7, y: -snake.radius - 7, width: (snake.radius + 7) * 2, height: (snake.radius + 7) * 2), transform: nil)
        shield.position = headPoint
        shield.strokeColor = snake.power?.kind == .shield ? .systemCyan : UIColor.white.withAlphaComponent(0.3)
        shield.lineWidth = snake.power?.kind == .shield ? 3 : 1
        shield.isHidden = snake.power?.kind != .shield && snake.protection <= 0
        root.zPosition = snake.mass
    }
}
