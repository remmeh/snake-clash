import Foundation

struct Point: Equatable, Codable {
    var x: Double
    var y: Double
}

enum PowerKind: String, Codable, CaseIterable {
    case ghost, dash, bigBite, magnet, shield, quickTurn, appetite, chill
    var title: String {
        switch self {
        case .ghost: return "Ghost"
        case .dash: return "Super Dash"
        case .bigBite: return "Big Bite"
        case .magnet: return "Snack Magnet"
        case .shield: return "Bubble Shield"
        case .quickTurn: return "Quick Turn"
        case .appetite: return "Golden Appetite"
        case .chill: return "Chill Burst"
        }
    }
    var symbol: String {
        switch self {
        case .ghost: return "👻"
        case .dash: return "⚡"
        case .bigBite: return "🎈"
        case .magnet: return "🧲"
        case .shield: return "🛡"
        case .quickTurn: return "🌀"
        case .appetite: return "✨"
        case .chill: return "❄"
        }
    }
    var duration: Double {
        switch self {
        case .ghost, .appetite: return 6
        case .dash, .bigBite: return 5
        case .magnet: return 8
        case .shield: return 10
        case .quickTurn: return 7
        case .chill: return 3
        }
    }
}
enum PowerSound: Equatable {
    case pickup(PowerKind)
    case shieldBreak
}

struct ActivePower: Codable {
    let kind: PowerKind
    var remaining: Double
}
struct PowerPickup: Codable {
    var id = UUID()
    let kind: PowerKind
    var position: Point
    var lifetime = 45.0
}

final class Snake: Codable {
    let id: Int
    let name: String
    let colorIndex: Int
    var position: Point
    var trail: [Point]
    var mass: Double
    var angle: Double
    var target: Double
    var alive = true
    var protection = 2.0
    var thinking = 0.0
    var power: ActivePower?
    var slowedFor: Double?
    var pickupCooldown: Double?
    var effectiveMass: Double { mass * (power?.kind == .bigBite ? 2 : 1) }
    var radius: Double { (9 + sqrt(mass) * 0.48) * (power?.kind == .bigBite ? sqrt(2) : 1) }

    init(id: Int, name: String, position: Point, mass: Double, angle: Double, colorIndex: Int) {
        self.id = id; self.name = name; self.position = position
        self.mass = mass; self.angle = angle; target = angle; self.colorIndex = colorIndex
        trail = (0..<Int(30 + mass * 0.65)).map {
            Point(x: GameWorld.wrap(position.x - cos(angle) * Double($0) * 3),
                  y: GameWorld.wrap(position.y - sin(angle) * Double($0) * 3))
        }
    }
}

struct Food: Codable {
    let id: Int
    var position: Point
    let value: Int
    let radius: Double
}

struct SnackEvent {
    let position: Point
    let name: String
    let count: Int
}

/// Pure Swift simulation, shared by the SpriteKit scene and command-line checks.
final class GameWorld {
    static let size = 2600.0
    static func wrap(_ n: Double) -> Double { (n.truncatingRemainder(dividingBy: size) + size).truncatingRemainder(dividingBy: size) }
    static func delta(_ a: Double, _ b: Double) -> Double {
        let difference = a - b
        if difference >= size / 2 { return difference - size }
        if difference < -size / 2 { return difference + size }
        return difference
    }
    static func distanceSquared(_ a: Point, _ b: Point) -> Double {
        let x = delta(a.x, b.x), y = delta(a.y, b.y)
        return x * x + y * y
    }
    static func distance(_ a: Point, _ b: Point) -> Double { sqrt(distanceSquared(a, b)) }
    var snakes: [Snake] = []
    var food: [Food] = []
    var player: Snake { snakes[0] }
    var score = 0
    var eaten = 0
    var energy = 1.0
    var time = 0.0
    var isOver = false
    var events: [SnackEvent] = []
    var collectedDots = 0
    var pickups: [PowerPickup] = []
    var powerMessage: String?
    var powerSounds: [PowerSound] = []
    private var nextPowerSpawn = 12.0
    private var nextFoodID = 0
    private var respawns: [(id: Int, at: Double)] = []
    private let names = ["Noodle", "Pickle", "Ziggy", "Mochi", "Squiggle", "Basil", "Peaches", "Wiggles", "Sprout", "Bean", "Olive", "Bubbles"]

    init() { reset() }

    func makeBot(_ id: Int) -> Snake {
        Snake(id: id, name: names[(id - 1) % names.count],
              position: Point(x: .random(in: 0..<Self.size), y: .random(in: 0..<Self.size)),
              mass: .random(in: 28...180), angle: .random(in: -.pi ... .pi), colorIndex: (id - 1) % 6)
    }

    func reset() {
        score = 0; eaten = 0; energy = 1; time = 0; isOver = false; collectedDots = 0
        events.removeAll(); respawns.removeAll(); food.removeAll(); nextFoodID = 0
        pickups.removeAll(); powerSounds.removeAll(); powerMessage = nil; nextPowerSpawn = 12
        snakes = [Snake(id: 0, name: "You", position: Point(x: 1300, y: 1300), mass: 70, angle: .pi / 5, colorIndex: 6)]
        for id in 1...12 { snakes.append(makeBot(id)) }
        let nearby: [(Double, Double, Double)] = [(130, 160, 32), (-170, -110, 42), (420, -240, 105)]
        for (index, spot) in nearby.enumerated() {
            snakes[index + 1] = Snake(id: index + 1, name: names[index], position: Point(x: 1300 + spot.0, y: 1300 + spot.1), mass: spot.2, angle: 2.4, colorIndex: index)
        }
        for _ in 0..<6 { spawnPower() }
        pickups[0].position = Point(x: 1480, y: 1300)
        for _ in 0..<650 { addFood(at: Point(x: .random(in: 0..<Self.size), y: .random(in: 0..<Self.size))) }
    }

    private func spawnPower() {
        // Big Bite has one quarter of the weight of each other pickup.
        let choices = PowerKind.allCases.filter { $0 != .bigBite }
        let kind = Int.random(in: 0..<29) == 0 ? PowerKind.bigBite : choices.randomElement()!
        pickups.append(PowerPickup(kind: kind, position: Point(x: .random(in: 0..<Self.size), y: .random(in: 0..<Self.size))))
    }

    @discardableResult
    func activate(_ kind: PowerKind, for snake: Snake) -> Bool {
        guard snake.alive, snake.power == nil, (snake.pickupCooldown ?? 0) <= 0 else { return false }
        snake.power = ActivePower(kind: kind, remaining: kind.duration)
        if kind == .chill {
            for other in snakes where other.alive && other.id != snake.id && Self.distanceSquared(other.position, snake.position) < 260 * 260 {
                other.slowedFor = max(other.slowedFor ?? 0, 3)
            }
        }
        // Reconsider targets immediately when Ghost appears.
        for other in snakes { other.thinking = 0 }
        if snake.id == 0 { powerSounds.append(.pickup(kind)); powerMessage = "\(kind.symbol) \(kind.title) · \(Int(kind.duration)) seconds!" }
        return true
    }

    func addFood(at point: Point, value: Int = 1) {
        food.append(Food(id: nextFoodID, position: Point(x: Self.wrap(point.x), y: Self.wrap(point.y)), value: value, radius: .random(in: 2.5...4.5)))
        nextFoodID += 1
    }

    func eat(_ winner: Snake, _ loser: Snake) {
        guard loser.alive else { return }
        if loser.power?.kind == .shield {
            loser.power = nil; loser.protection = 1.5; loser.pickupCooldown = 4
            if loser.id == 0 { powerSounds.append(.shieldBreak); powerMessage = "Shield popped! Make your escape." }
            return
        }
        loser.alive = false
        let count = min(140, Int(loser.mass * 0.6) + 20)
        for _ in 0..<count {
            let point = loser.trail.randomElement() ?? loser.position
            addFood(at: Point(x: point.x + .random(in: -28...28), y: point.y + .random(in: -28...28)), value: 2)
        }
        winner.mass += 5
        if winner.id == 0 {
            score += 50; eaten += 1
            events.append(SnackEvent(position: loser.position, name: loser.name, count: count))
        }
        if loser.id == 0 { isOver = true }
        else { respawns.append((loser.id, time + 3)) }
    }

    func update(_ elapsed: Double, angle: Double, boost: Bool) {
        collectedDots = 0
        guard !isOver else { return }
        let dt = min(max(elapsed, 0), 0.04)
        time += dt
        for snake in snakes where snake.alive {
            if var power = snake.power {
                power.remaining -= dt
                if power.remaining <= 0 { snake.power = nil; snake.pickupCooldown = 4 }
                else { snake.power = power }
            }
            snake.slowedFor = max(0, (snake.slowedFor ?? 0) - dt)
            snake.pickupCooldown = max(0, (snake.pickupCooldown ?? 0) - dt)
        }
        for i in pickups.indices {
            pickups[i].lifetime -= dt
            pickups[i].position.x = Self.wrap(pickups[i].position.x + cos(time * 0.35 + Double(i)) * 7 * dt)
            pickups[i].position.y = Self.wrap(pickups[i].position.y + sin(time * 0.3 + Double(i)) * 7 * dt)
        }
        pickups.removeAll { $0.lifetime <= 0 }
        if time >= nextPowerSpawn {
            if pickups.count < 6 { spawnPower() }
            nextPowerSpawn = time + 12
        }
        let dashing = boost && energy > 0.03 && player.power?.kind != .dash
        energy = min(1, max(0, energy + dt * (dashing ? -0.24 : 0.14)))
        player.target = angle
        for snake in snakes where snake.alive {
            snake.protection = max(0, snake.protection - dt)
            if snake.id != 0 {
                snake.thinking -= dt
                if snake.thinking <= 0 {
                    snake.thinking = .random(in: 0.4...1.3)
                    let neighbors = snakes.filter { $0.alive && $0.id != snake.id && $0.power?.kind != .ghost && Self.distanceSquared($0.position, snake.position) < 90_000 }
                    if let threat = neighbors.filter({ $0.effectiveMass > snake.effectiveMass * 1.12 }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(snake.position.y, threat.position.y), Self.delta(snake.position.x, threat.position.x))
                    } else if let prey = neighbors.filter({ $0.effectiveMass * 1.12 < snake.effectiveMass }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(prey.position.y, snake.position.y), Self.delta(prey.position.x, snake.position.x))
                    } else if snake.power == nil, (snake.pickupCooldown ?? 0) <= 0,
                              let pickup = pickups.filter({ Self.distanceSquared($0.position, snake.position) < 320 * 320 }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(pickup.position.y, snake.position.y), Self.delta(pickup.position.x, snake.position.x))
                    } else if let bite = stride(from: 0, to: food.count, by: 4).lazy.map({ self.food[$0] }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(bite.position.y, snake.position.y), Self.delta(bite.position.x, snake.position.x))
                    }
                }
            }
            let turn = atan2(sin(snake.target - snake.angle), cos(snake.target - snake.angle))
            let turning = snake.power?.kind == .quickTurn ? 6.2 : 3.1
            snake.angle += min(dt * turning, max(-dt * turning, turn))
            let speedMultiplier = snake.power?.kind == .dash ? 1.6 : (snake.id == 0 && dashing ? 1.85 : 1)
            let speed = (snake.id == 0 ? 110.0 : 78.0) * speedMultiplier * ((snake.slowedFor ?? 0) > 0 ? 0.75 : 1)
            snake.position.x = Self.wrap(snake.position.x + cos(snake.angle) * speed * dt)
            snake.position.y = Self.wrap(snake.position.y + sin(snake.angle) * speed * dt)
            if let first = snake.trail.first, Self.distance(first, snake.position) >= 3 {
                snake.trail.insert(snake.position, at: 0)
                let length = min(1200, Int(30 + snake.mass * 0.65))
                if snake.trail.count > length { snake.trail.removeLast(snake.trail.count - length) }
            }
            if let index = pickups.firstIndex(where: { Self.distanceSquared(snake.position, $0.position) < pow(snake.radius + 16, 2) }),
               activate(pickups[index].kind, for: snake) { pickups.remove(at: index) }
            if snake.power?.kind == .magnet {
                for index in food.indices {
                    let bite = food[index].position
                    let distance = Self.distance(snake.position, bite)
                    if distance > 0 && distance < 150 {
                        let step = min(1, dt * 180 / distance)
                        food[index].position.x = Self.wrap(bite.x + Self.delta(snake.position.x, bite.x) * step)
                        food[index].position.y = Self.wrap(bite.y + Self.delta(snake.position.y, bite.y) * step)
                    }
                }
            }
            food.removeAll { bite in
                if Self.distanceSquared(snake.position, bite.position) < (snake.radius + 5) * (snake.radius + 5) {
                    snake.mass += Double(bite.value) * 0.55 * (snake.power?.kind == .appetite ? 1.5 : 1)
                    if snake.id == 0 { score += bite.value * 2; collectedDots += 1 }
                    return true
                }
                return false
            }
        }
        for i in snakes.indices where snakes[i].alive {
            for j in snakes.indices where j > i && snakes[j].alive && snakes[i].alive {
                let a = snakes[i], b = snakes[j]
                guard a.protection == 0 && b.protection == 0 else { continue }
                let big = a.effectiveMass > b.effectiveMass ? a : b, small = a.effectiveMass > b.effectiveMass ? b : a
                guard big.effectiveMass > small.effectiveMass * 1.08 else { continue }
                let reach = (big.radius + small.radius) * (big.radius + small.radius)
                let hit = Self.distanceSquared(big.position, small.position) < reach
                    || stride(from: 0, to: small.trail.count, by: 4).contains { Self.distanceSquared(big.position, small.trail[$0]) < reach }
                    || stride(from: 0, to: big.trail.count, by: 4).contains { Self.distanceSquared(small.position, big.trail[$0]) < reach }
                if hit { eat(big, small) }
            }
        }
        for entry in respawns where entry.at <= time {
            let bot = makeBot(entry.id)
            if Self.distance(bot.position, player.position) < 500 {
                bot.position = Point(x: Self.wrap(player.position.x + 900), y: Self.wrap(player.position.y + 900))
                bot.trail = [bot.position]
            }
            if let index = snakes.firstIndex(where: { $0.id == entry.id }) { snakes[index] = bot }
        }
        respawns.removeAll { $0.at <= time }
        while food.count < 650 { addFood(at: Point(x: .random(in: 0..<Self.size), y: .random(in: 0..<Self.size))) }
        if food.count > 1800 { food.removeFirst(food.count - 1800) }
    }
}

extension GameWorld {
    private struct SavedRound: Codable {
        let version: Int
        let snakes: [Snake]
        let food: [Food]
        let score: Int
        let eaten: Int
        let energy: Double
        let time: Double
        let nextFoodID: Int
        let respawns: [Int: Double]
        var pickups: [PowerPickup]?
        var nextPowerSpawn: Double?
    }

    func saveData() -> Data? {
        guard !isOver, player.alive else { return nil }
        let round = SavedRound(version: 1, snakes: snakes, food: food, score: score,
            eaten: eaten, energy: energy, time: time, nextFoodID: nextFoodID,
            respawns: Dictionary(uniqueKeysWithValues: respawns.map { ($0.id, $0.at) }), pickups: pickups, nextPowerSpawn: nextPowerSpawn)
        return try? JSONEncoder().encode(round)
    }

    @discardableResult
    func restore(from data: Data) -> Bool {
        guard let round = try? JSONDecoder().decode(SavedRound.self, from: data),
              round.version == 1, round.snakes.first?.id == 0,
              round.snakes.first?.alive == true,
              round.energy >= 0, round.energy <= 1,
              Set(round.snakes.map(\.id)).count == round.snakes.count,
              round.snakes.allSatisfy({ !$0.trail.isEmpty && $0.mass > 0 }) else { return false }
        snakes = round.snakes; food = round.food; score = round.score
        eaten = round.eaten; energy = round.energy; time = round.time
        nextFoodID = round.nextFoodID
        respawns = round.respawns.map { (id: $0.key, at: $0.value) }
        pickups = round.pickups ?? []
        nextPowerSpawn = round.nextPowerSpawn ?? (time + 2)
        powerMessage = nil; powerSounds.removeAll()
        isOver = false; events.removeAll(); collectedDots = 0
        return true
    }
}
