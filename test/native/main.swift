import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
    print("PASS: \(message)")
}
func isolated() -> GameWorld {
    let world = GameWorld()
    world.snakes = [world.player]
    world.food = []
    return world
}
check(GameWorld.wrap(-5) == 2595, "world coordinates wrap")
check(GameWorld.distance(Point(x: 1, y: 0), Point(x: 2599, y: 0)) == 2, "collision distance crosses world seam")
let snack = isolated()
let rival = Snake(id: 1, name: "Snack", position: snack.player.position, mass: 30, angle: 0, colorIndex: 0)
snack.snakes.append(rival); snack.player.protection = 0; rival.protection = 0
snack.update(0.016, angle: 0, boost: false)
check(!rival.alive && snack.eaten == 1 && snack.score >= 50, "native collision eats the smaller snake")
check(snack.food.filter { $0.value == 2 }.count == 38, "eaten rival bursts into 38 yellow balls")
let danger = isolated()
let big = Snake(id: 1, name: "Big", position: danger.player.position, mass: 200, angle: 0, colorIndex: 1)
danger.snakes.append(big); danger.player.protection = 0; big.protection = 0
danger.update(0.016, angle: 0, boost: false)
check(danger.isOver && !danger.player.alive, "bigger snake ends the round")
let food = isolated(), mass = 70.0
food.addFood(at: food.player.position, value: 2); food.update(0.016, angle: 0, boost: false)
check(food.score == 4 && food.player.mass > mass, "yellow balls grow the snake and score")
check(food.collectedDots == 1, "player dot collection emits sound signal")
food.food = []; food.update(0.016, angle: 0, boost: false)
check(food.collectedDots == 0, "collection sound signal clears on the next frame")
let botFood = isolated()
let bot = Snake(id: 1, name: "Bot", position: Point(x: 600, y: 600), mass: 30, angle: 0, colorIndex: 0)
botFood.snakes.append(bot); botFood.addFood(at: bot.position)
botFood.update(0.016, angle: 0, boost: false)
check(botFood.collectedDots == 0, "rival dot collection stays silent")
let boost = isolated()
for _ in 0..<25 { boost.update(0.04, angle: 0, boost: true) }
let drained = boost.energy
check(drained < 0.8, "boost spends energy")
for _ in 0..<25 { boost.update(0.04, angle: 0, boost: false) }
check(boost.energy > drained, "energy recovers after boost")
let round = GameWorld(); round.player.protection = 1000
for index in 0..<3600 { round.update(1.0 / 60, angle: Double(index) * 0.002, boost: index % 200 < 50) }
check(!round.isOver && round.snakes.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite }, "60-second native simulation stays valid")
check(round.food.count <= 1800 && round.food.count >= 650, "native simulation bounds food count")
func samples(_ data: Data) -> [Int16] {
    stride(from: 44, to: data.count, by: 2).map {
        Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)
    }
}
let bed = SoundSynthesis.ambient(), dot = SoundSynthesis.dot(frequency: 880), chomp = SoundSynthesis.snake()
let death = SoundSynthesis.death()
for (name, data, duration) in [("ambient", bed, 8.0), ("dot", dot, 0.16), ("snake", chomp, 0.65), ("death", death, 0.55)] {
    check(String(data: data.prefix(4), encoding: .utf8) == "RIFF" && String(data: data[8..<12], encoding: .utf8) == "WAVE", "\(name) is a valid WAV container")
    let pcm = samples(data)
    check(pcm.count == Int(Double(SoundSynthesis.sampleRate) * duration), "\(name) has the expected duration")
    let peak = pcm.map { abs(Int($0)) }.max() ?? 0
    check(peak > 100 && peak < 32000, "\(name) contains audible, unclipped samples")
}
let bedPCM = samples(bed)
let loopStep = Int(bedPCM[0]) - Int(bedPCM[bedPCM.count - 1])
let nextStep = Int(bedPCM[1]) - Int(bedPCM[0])
check(abs(loopStep - nextStep) < 100, "ambient loop has a smooth seam")
check(abs(Int(samples(dot).last!)) < 50 && abs(Int(samples(chomp).last!)) < 50, "eating sounds taper to silence")
check(abs(Int(samples(death).last!)) < 50, "death cue fades to silence")
let bedRMS = sqrt(bedPCM.reduce(0.0) { sum, sample in
    let level = Double(sample) / 32768
    return sum + level * level
} / Double(bedPCM.count))
check(bedRMS * 0.6 > 0.03, "ambient loop maintains a clear playback level")
print("\(checks) native gameplay and audio checks passed")


// A redeploy preserves UserDefaults; this exercises the saved-round payload it stores.
let saved = GameWorld()
saved.score = 1234; saved.player.mass = 210; saved.energy = 0.42
let payload = saved.saveData()!
let restored = GameWorld()
check(restored.restore(from: payload), "saved round loads into a fresh game")
check(restored.score == 1234 && restored.player.mass == 210 && restored.energy == 0.42,
      "score, growth and boost survive saving")
check(restored.player.position == saved.player.position && restored.food.count == saved.food.count,
      "arena and position survive saving")
check(!restored.restore(from: Data("invalid".utf8)) && restored.score == 1234,
      "invalid save does not damage the current round")
restored.update(0.016, angle: restored.player.angle, boost: false)
check(!restored.isOver, "restored round can continue playing")
print("Saved-round checks passed")
