import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try SoundSynthesis.ambient().write(to: directory.appendingPathComponent("ambient.wav"))
for (index, frequency) in [659.25, 739.99, 880.0, 987.77, 1108.73, 880.0].enumerated() {
    try SoundSynthesis.dot(frequency: frequency).write(to: directory.appendingPathComponent("dot-\(index).wav"))
}
try SoundSynthesis.snake().write(to: directory.appendingPathComponent("snake.wav"))
try SoundSynthesis.death().write(to: directory.appendingPathComponent("death.wav"))
for kind in PowerKind.allCases {
    try SoundSynthesis.powerUp(kind).write(to: directory.appendingPathComponent("power-\(kind.rawValue).wav"))
}
try SoundSynthesis.shieldBreak().write(to: directory.appendingPathComponent("shield-break.wav"))
