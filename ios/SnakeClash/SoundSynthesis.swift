import Foundation

/// PCM WAV generation kept independent from playback so assets can be verified offline.
enum SoundSynthesis {
    static let sampleRate = 22050
    private static let tau = Double.pi * 2

    static func ambient() -> Data {
        // Exact eight-second periods keep the pad seamless at the loop point.
        let frequencies = [130.875, 164.875, 196.0, 246.875, 293.625]
        let melody = [392.0, 523.25, 659.25, 587.33, 493.88, 392.0]
        return wave(duration: 8) { t in
            var value = 0.0
            for (index, frequency) in frequencies.enumerated() {
                let breath = 0.65 + 0.25 * sin(tau * t / 8 + Double(index))
                value += sin(tau * frequency * t) * breath * 0.065
                value += sin(tau * frequency * 2 * t) * breath * 0.012
            }
            // Slow bell notes give the pad a recognizable melody on small speakers.
            for (index, note) in melody.enumerated() {
                let local = t - Double(index) * 1.25
                if local >= 0 && local < 1.7 {
                    let envelope = min(1, local / 0.035) * exp(-local * 2.7)
                        * min(1, (1.7 - local) / 0.2)
                    value += sin(tau * note * local) * envelope * 0.11
                }
            }
            return value
        }
    }

    static func dot(frequency: Double) -> Data {
        wave(duration: 0.16) { t in
            let attack = min(1, t / 0.005)
            let release = min(1, (0.16 - t) / 0.025)
            let envelope = attack * release * exp(-t * 23)
            return envelope * (sin(tau * frequency * t) * 0.42 + sin(tau * frequency * 2 * t) * 0.07)
        }
    }

    static func snake() -> Data {
        wave(duration: 0.65) { t in
            var value = 0.0
            for (index, frequency) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                let local = t - Double(index) * 0.07
                if local >= 0 {
                    let envelope = min(1, local / 0.006) * exp(-local * 10) * min(1, (0.65 - t) / 0.04)
                    value += sin(tau * frequency * local) * envelope * 0.19
                }
            }
            // A rounded low pop underneath the rising reward chime.
            value += sin(tau * (140 * t - 55 * t * t)) * exp(-t * 30) * min(1, t / 0.004) * 0.15
            return value
        }
    }

    static func death() -> Data {
        let duration = 0.55
        let notes = [392.0, 293.66, 196.0]
        return wave(duration: duration) { t in
            var value = 0.0
            for (index, note) in notes.enumerated() {
                let local = t - Double(index) * 0.10
                guard local >= 0 else { continue }
                let envelope = min(1, local / 0.01) * exp(-local * 12)
                    * min(1, (duration - t) / 0.06)
                let phase = tau * (note * local - 28 * local * local)
                value += envelope * (sin(phase) * 0.29 + sin(phase * 2) * 0.055)
            }
            return value
        }
    }

    private static func wave(duration: Double, sample: (Double) -> Double) -> Data {
        let count = Int(Double(sampleRate) * duration)
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1))
        word(UInt16(1)); word(UInt32(sampleRate)); word(UInt32(sampleRate * 2))
        word(UInt16(2)); word(UInt16(16)); data.append(contentsOf: "data".utf8); word(UInt32(count * 2))
        data.reserveCapacity(44 + count * 2)
        for frame in 0..<count {
            let value = max(-1, min(1, sample(Double(frame) / Double(sampleRate))))
            word(Int16(value * 32767))
        }
        return data
    }
}
