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

func powerWorld() -> GameWorld {
    let world = isolated()
    world.pickups = []
    world.player.protection = 1000
    world.player.angle = 0; world.player.target = 0
    return world
}
let powers = powerWorld()
for kind in PowerKind.allCases {
    powers.player.power = nil; powers.player.pickupCooldown = nil
    check(powers.activate(kind, for: powers.player), "\(kind.title) can activate")
    check(!powers.activate(kind, for: powers.player), "\(kind.title) cannot stack or refresh")
}
let giant = powerWorld()
let originalMass = giant.player.mass, originalRadius = giant.player.radius
giant.activate(.bigBite, for: giant.player)
check(giant.player.effectiveMass == originalMass * 2 && giant.player.radius > originalRadius, "Big Bite increases combat strength and visible size")
giant.addFood(at: giant.player.position)
giant.update(0, angle: 0, boost: false)
let grownMass = giant.player.mass
giant.player.power?.remaining = 0.01
giant.update(0.02, angle: 0, boost: false)
check(giant.player.power == nil && giant.player.mass == grownMass && giant.player.effectiveMass == grownMass, "Big Bite expiry preserves collected growth")
check(!giant.activate(.shield, for: giant.player), "power cooldown prevents chaining")
let dash = powerWorld(), normal = powerWorld()
dash.activate(.dash, for: dash.player)
let startPoint = dash.player.position
dash.update(0.04, angle: 0, boost: true); normal.update(0.04, angle: 0, boost: false)
check(abs(GameWorld.distance(startPoint, dash.player.position) / GameWorld.distance(startPoint, normal.player.position) - 1.6) < 0.001 && dash.energy == 1, "Super Dash is 60% faster and cannot stack with paid boost")
let turn = powerWorld()
turn.activate(.quickTurn, for: turn.player); turn.update(0.04, angle: .pi / 2, boost: false)
check(abs(turn.player.angle - 0.248) < 0.001, "Quick Turn doubles turning speed")
let magnet = powerWorld()
magnet.activate(.magnet, for: magnet.player)
magnet.addFood(at: Point(x: 1400, y: 1300))
let foodID = magnet.food[0].id
magnet.update(0.04, angle: 0, boost: false)
check(magnet.food.first { $0.id == foodID }!.position.x < 1400, "Magnet pulls nearby food")
let appetite = powerWorld()
appetite.activate(.appetite, for: appetite.player); appetite.addFood(at: appetite.player.position)
appetite.update(0, angle: 0, boost: false)
check(abs(appetite.player.mass - 70.825) < 0.001 && appetite.score == 2, "Golden Appetite increases food growth by 50% without increasing score")
let shieldWorld = powerWorld()
let attacker = Snake(id: 1, name: "Threat", position: shieldWorld.player.position, mass: 300, angle: 0, colorIndex: 0)
shieldWorld.activate(.shield, for: shieldWorld.player)
shieldWorld.eat(attacker, shieldWorld.player)
check(shieldWorld.player.alive && !shieldWorld.isOver && shieldWorld.player.power == nil && shieldWorld.player.protection == 1.5, "Shield absorbs one hit and grants an escape window")
let ghost = powerWorld()
let hunter = Snake(id: 1, name: "Hunter", position: Point(x: 1320, y: 1300), mass: 300, angle: 1, colorIndex: 0)
ghost.snakes.append(hunter); ghost.activate(.ghost, for: ghost.player)
ghost.update(0, angle: 0, boost: false)
check(hunter.target == 1, "Ghost is excluded from rival targeting")
ghost.eat(hunter, ghost.player)
check(ghost.isOver, "Ghost still loses a collision with a bigger snake")
let chill = powerWorld()
let nearby = Snake(id: 1, name: "Nearby", position: Point(x: 1400, y: 1300), mass: 30, angle: 0, colorIndex: 0)
let far = Snake(id: 2, name: "Far", position: Point(x: 2000, y: 1300), mass: 30, angle: 0, colorIndex: 1)
chill.snakes += [nearby, far]; chill.activate(.chill, for: chill.player)
check(nearby.slowedFor == 3 && far.slowedFor == nil, "Chill Burst affects only nearby rivals")
let pickupWorld = powerWorld()
pickupWorld.pickups = [PowerPickup(kind: .shield, position: pickupWorld.player.position)]
pickupWorld.update(0, angle: 0, boost: false)
check(pickupWorld.player.power?.kind == .shield && pickupWorld.pickups.isEmpty, "touching a floating pickup consumes it")
let rivalPickup = powerWorld()
let collector = Snake(id: 1, name: "Collector", position: Point(x: 600, y: 600), mass: 40, angle: 0, colorIndex: 0)
rivalPickup.snakes.append(collector)
rivalPickup.pickups = [PowerPickup(kind: .magnet, position: collector.position)]
rivalPickup.update(0, angle: 0, boost: false)
check(collector.power?.kind == .magnet && rivalPickup.pickups.isEmpty, "rivals can collect power-ups")
let savedPowers = GameWorld()
savedPowers.activate(.dash, for: savedPowers.player)
savedPowers.player.slowedFor = 2
let restoredPowers = GameWorld()
check(restoredPowers.restore(from: savedPowers.saveData()!) && restoredPowers.player.power?.kind == .dash && restoredPowers.pickups.count == savedPowers.pickups.count && restoredPowers.player.slowedFor == 2, "power effects and floating pickups survive save/restore")
var legacy = try JSONSerialization.jsonObject(with: savedPowers.saveData()!) as! [String: Any]
legacy.removeValue(forKey: "pickups"); legacy.removeValue(forKey: "nextPowerSpawn")
var legacySnakes = legacy["snakes"] as! [[String: Any]]
for index in legacySnakes.indices {
    legacySnakes[index].removeValue(forKey: "power")
    legacySnakes[index].removeValue(forKey: "slowedFor")
    legacySnakes[index].removeValue(forKey: "pickupCooldown")
}
legacy["snakes"] = legacySnakes
let legacyData = try JSONSerialization.data(withJSONObject: legacy)
check(restoredPowers.restore(from: legacyData) && restoredPowers.player.power == nil, "old saved rounds load without power-up fields")
print("All \(checks) native checks passed")

var pickupWaves = Set<Data>()
for kind in PowerKind.allCases {
    let audioWorld = powerWorld()
    audioWorld.activate(kind, for: audioWorld.player)
    check(audioWorld.powerSounds == [.pickup(kind)], "\(kind.title) emits its own pickup sound")
    audioWorld.activate(kind, for: audioWorld.player)
    check(audioWorld.powerSounds.count == 1, "blocked pickup does not repeat audio")
    let data = SoundSynthesis.powerUp(kind)
    pickupWaves.insert(data)
    let pcm = samples(data)
    let peak = pcm.map { abs(Int($0)) }.max()!
    check(peak > 100 && peak < 32000 && abs(Int(pcm.last!)) < 50, "\(kind.title) audio is nonclipping and fades out")
    let bundled = try Data(contentsOf: URL(fileURLWithPath: "ios/SnakeClash/Audio/power-\(kind.rawValue).wav"))
    check(bundled == data, "\(kind.title) bundled audio matches the generator")
}
check(pickupWaves.count == 8, "all eight power-ups have distinct sounds")
let audioShield = powerWorld()
audioShield.activate(.shield, for: audioShield.player)
audioShield.powerSounds.removeAll()
audioShield.eat(attacker, audioShield.player)
check(audioShield.powerSounds == [.shieldBreak], "shield breaking emits one pop")
check(rivalPickup.powerSounds.isEmpty, "rival pickups do not trigger player audio")
let reloadSound = GameWorld()
reloadSound.restore(from: savedPowers.saveData()!)
check(reloadSound.powerSounds.isEmpty, "restoring a buff does not replay its pickup sound")
let popPCM = samples(SoundSynthesis.shieldBreak())
check(popPCM.map { abs(Int($0)) }.max()! < 32000 && abs(Int(popPCM.last!)) < 50, "shield pop stays unclipped and fades out")
print("All \(checks) gameplay and audio checks passed")
