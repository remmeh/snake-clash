import AVFoundation
import UIKit

/// Small, original synthesized sounds. No downloads or network access are needed.
final class GameAudio: NSObject {
    var isEnabled = true { didSet { synchronize() } }
    private var wantsPlayback = false
    private var interrupted = false
    private var backgrounded = false
    private var ambient: AVAudioPlayer?
    private var dotVoices: [AVAudioPlayer] = []
    private var snakeVoice: AVAudioPlayer?
    private var deathVoice: AVAudioPlayer?
    private var powerVoice: AVAudioPlayer?
    private var voiceIndex = 0
    private var lastDot = -Double.infinity

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interruption), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(background), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        if playing { interrupted = false }
        synchronize()
    }

    private var soundAllowed: Bool { isEnabled && !interrupted && !backgrounded }
    private var canPlay: Bool { soundAllowed && wantsPlayback }

    private func player(named name: String) throws -> AVAudioPlayer {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio") else {
            throw NSError(domain: "SnakeClash.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing audio: " + name])
        }
        return try AVAudioPlayer(contentsOf: url)
    }

    private func prepare() throws {
        guard ambient == nil else { return }
        // Ambient respects the iPad's Silent Mode and lets other apps keep their music.
        try AVAudioSession.sharedInstance().setCategory(.ambient)
        let bed = try player(named: "ambient")
        bed.numberOfLoops = -1; bed.volume = 0.6; bed.prepareToPlay()
        var voices: [AVAudioPlayer] = []
        for index in 0..<6 {
            let voice = try player(named: "dot-\(index)")
            voice.volume = 0.55; voice.prepareToPlay(); voices.append(voice)
        }
        let chomp = try player(named: "snake")
        chomp.volume = 0.65; chomp.prepareToPlay()
        let death = try player(named: "death")
        death.volume = 0.65; death.prepareToPlay()
        ambient = bed; dotVoices = voices; snakeVoice = chomp; deathVoice = death
    }

    private func synchronize() {
        deathVoice?.stop(); deathVoice?.currentTime = 0
        powerVoice?.stop(); powerVoice?.currentTime = 0
        guard canPlay else {
            ambient?.pause()
            dotVoices.forEach { $0.stop(); $0.currentTime = 0 }
            snakeVoice?.stop(); snakeVoice?.currentTime = 0
            return
        }
        do {
            try prepare()
            try AVAudioSession.sharedInstance().setActive(true)
            if ambient?.isPlaying == false { ambient?.play() }
        } catch {
            // Audio failure must never interrupt gameplay; retry on the next resume.
            #if DEBUG
            print("Snake Clash audio unavailable: \(error)")
            #endif
        }
    }

    func collectDot(at time: Double) {
        guard canPlay, time - lastDot >= 0.075, !dotVoices.isEmpty else { return }
        lastDot = time
        let voice = dotVoices[voiceIndex % dotVoices.count]
        voiceIndex += 1; voice.currentTime = 0; voice.play()
    }

    func eatSnake(at time: Double) {
        guard canPlay else { return }
        lastDot = time + 0.15
        snakeVoice?.currentTime = 0; snakeVoice?.play()
    }

    func playPower(_ event: PowerSound, at time: Double) {
        guard canPlay else { return }
        let name: String
        switch event {
        case .pickup(let kind): name = "power-" + kind.rawValue
        case .shieldBreak: name = "shield-break"
        }
        do {
            let voice = try player(named: name)
            voice.volume = 0.7
            powerVoice?.stop()
            powerVoice = voice
            dotVoices.forEach { $0.stop() }
            lastDot = time + 0.2
            voice.play()
        } catch {
            #if DEBUG
            print("Power-up sound unavailable: \(error)")
            #endif
        }
    }

    // Called after gameplay stops so the game-over cue can finish on the menu.
    func playDeath() {
        guard soundAllowed else { return }
        deathVoice?.currentTime = 0; deathVoice?.play()
    }

    @objc private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { interrupted = true }
        else {
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            interrupted = !AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
        }
        synchronize()
    }
    @objc private func background() { backgrounded = true; synchronize() }
    @objc private func foreground() { backgrounded = false; synchronize() }
}

