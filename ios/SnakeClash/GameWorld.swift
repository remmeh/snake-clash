import Foundation

struct Point: Equatable, Codable {
    var x: Double
    var y: Double
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
    var radius: Double { 9 + sqrt(mass) * 0.48 }

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
        snakes = [Snake(id: 0, name: "You", position: Point(x: 1300, y: 1300), mass: 70, angle: .pi / 5, colorIndex: 6)]
        for id in 1...12 { snakes.append(makeBot(id)) }
        let nearby: [(Double, Double, Double)] = [(130, 160, 32), (-170, -110, 42), (420, -240, 105)]
        for (index, spot) in nearby.enumerated() {
            snakes[index + 1] = Snake(id: index + 1, name: names[index], position: Point(x: 1300 + spot.0, y: 1300 + spot.1), mass: spot.2, angle: 2.4, colorIndex: index)
        }
        for _ in 0..<650 { addFood(at: Point(x: .random(in: 0..<Self.size), y: .random(in: 0..<Self.size))) }
    }

    func addFood(at point: Point, value: Int = 1) {
        food.append(Food(id: nextFoodID, position: Point(x: Self.wrap(point.x), y: Self.wrap(point.y)), value: value, radius: .random(in: 2.5...4.5)))
        nextFoodID += 1
    }

    func eat(_ winner: Snake, _ loser: Snake) {
        guard loser.alive else { return }
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
        let dashing = boost && energy > 0.03
        energy = min(1, max(0, energy + dt * (dashing ? -0.24 : 0.14)))
        player.target = angle
        for snake in snakes where snake.alive {
            snake.protection = max(0, snake.protection - dt)
            if snake.id != 0 {
                snake.thinking -= dt
                if snake.thinking <= 0 {
                    snake.thinking = .random(in: 0.4...1.3)
                    let neighbors = snakes.filter { $0.alive && $0.id != snake.id && Self.distanceSquared($0.position, snake.position) < 90_000 }
                    if let threat = neighbors.filter({ $0.mass > snake.mass * 1.12 }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(snake.position.y, threat.position.y), Self.delta(snake.position.x, threat.position.x))
                    } else if let prey = neighbors.filter({ $0.mass * 1.12 < snake.mass }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(prey.position.y, snake.position.y), Self.delta(prey.position.x, snake.position.x))
                    } else if let bite = stride(from: 0, to: food.count, by: 4).lazy.map({ self.food[$0] }).min(by: { Self.distanceSquared($0.position, snake.position) < Self.distanceSquared($1.position, snake.position) }) {
                        snake.target = atan2(Self.delta(bite.position.y, snake.position.y), Self.delta(bite.position.x, snake.position.x))
                    }
                }
            }
            let turn = atan2(sin(snake.target - snake.angle), cos(snake.target - snake.angle))
            snake.angle += min(dt * 3.1, max(-dt * 3.1, turn))
            let speed = (snake.id == 0 ? 110.0 : 78.0) * (snake.id == 0 && dashing ? 1.85 : 1)
            snake.position.x = Self.wrap(snake.position.x + cos(snake.angle) * speed * dt)
            snake.position.y = Self.wrap(snake.position.y + sin(snake.angle) * speed * dt)
            if let first = snake.trail.first, Self.distance(first, snake.position) >= 3 {
                snake.trail.insert(snake.position, at: 0)
                let length = min(1200, Int(30 + snake.mass * 0.65))
                if snake.trail.count > length { snake.trail.removeLast(snake.trail.count - length) }
            }
            food.removeAll { bite in
                if Self.distanceSquared(snake.position, bite.position) < (snake.radius + 5) * (snake.radius + 5) {
                    snake.mass += Double(bite.value) * 0.55
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
                let big = a.mass > b.mass ? a : b, small = a.mass > b.mass ? b : a
                guard big.mass > small.mass * 1.08 else { continue }
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
    }

    func saveData() -> Data? {
        guard !isOver, player.alive else { return nil }
        let round = SavedRound(version: 1, snakes: snakes, food: food, score: score,
            eaten: eaten, energy: energy, time: time, nextFoodID: nextFoodID,
            respawns: Dictionary(uniqueKeysWithValues: respawns.map { ($0.id, $0.at) }))
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
        isOver = false; events.removeAll(); collectedDots = 0
        return true
    }
}
