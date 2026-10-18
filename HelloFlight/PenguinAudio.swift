import AVFoundation
import UIKit

/// 効果音とBGMは開発用サウンドラボ（tools/sound-lab）で作り、ci/render-sounds.cjs で書き出したWAV（HelloFlight/Sounds）を鳴らす。
/// 読み上げは端末の音声合成を使う。
final class PenguinAudio: NSObject, AVSpeechSynthesizerDelegate {
    enum Sound: String, CaseIterable {
        case pop, pi, slide, jump, land, splash, correct, wrong, fanfare, sparkle
        case boing, whistle, squeak, pikopiko, bubble, whale, blub
    }

    /// たまに鳴る面白い音。まちがいと紛れないよう、上がる・弾む音だけ。
    static let funny: [Sound] = [.boing, .whistle, .squeak, .pikopiko, .bubble]

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private let music = AVAudioPlayerNode()
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var musicBuffer: AVAudioPCMBuffer?
    private var speech = AVSpeechSynthesizer()
    private var nextPlayer = 0
    private var started = false

    var enabled = true {
        didSet {
            updateMusicVolume()
            if !enabled { speech.stopSpeaking(at: .immediate) }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for sound in Sound.allCases { buffers[sound] = load(sound.rawValue) }
        musicBuffer = load("music")
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.attach(music)
        engine.connect(music, to: engine.mainMixerNode, format: format)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.resume() }
        // バックグラウンドからの復帰・電話などの割り込み終了・音声サービスの再起動で、音と読み上げを立て直す。
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.recover() }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.recover() }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in self?.recover() }
        // バックグラウンドでは音を止めておく（戻ったら didBecomeActive で再開）。
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() }
        resume()
    }

    /// 復帰後は読み上げが無音のまま止まることがあるため、音声セッションを有効にし直し、読み上げエンジンを作り直す。
    private func recover() {
        guard started else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        speech.delegate = nil
        speech.stopSpeaking(at: .immediate)
        speech = AVSpeechSynthesizer()
        speech.delegate = self
        resume()
    }

    private func suspend() {
        guard started else { return }
        speech.stopSpeaking(at: .immediate)
        engine.pause()
    }

    private func resume() {
        guard started else { return }
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            do { try engine.start() } catch { return }
        }
        if !music.isPlaying, let musicBuffer {
            music.scheduleBuffer(musicBuffer, at: nil, options: .loops)
            updateMusicVolume()
            music.play()
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard enabled, started else { return }
        if !engine.isRunning { resume() }
        guard engine.isRunning, let buffer = buffers[sound], !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    func playFunny() { play(Self.funny.randomElement() ?? .boing, volume: 0.9) }

    override init() {
        super.init()
        speech.delegate = self
    }

    /// BGMは控えめにし、読み上げ中はさらに下げて声を聞き取りやすくする。
    private func updateMusicVolume() {
        music.volume = enabled ? (speech.isSpeaking ? 0.03 : 0.1) : 0
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.updateMusicVolume() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.updateMusicVolume() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.updateMusicVolume() }
    }

    func say(_ parts: [PenguinSpeech]) {
        guard enabled else { return }
        speech.stopSpeaking(at: .immediate)
        for part in parts {
            let utterance = AVSpeechUtterance(string: part.text)
            utterance.voice = AVSpeechSynthesisVoice(language: part.language)
            // 3歳が聞き取りやすい、ゆっくりした速さ。
            utterance.rate = part.language.hasPrefix("ja") ? 0.36 : 0.32
            utterance.volume = 1
            utterance.pitchMultiplier = 1.2
            utterance.postUtteranceDelay = 0.08
            speech.speak(utterance)
        }
    }

    // MARK: - Files

    private func load(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        try? file.read(into: buffer)
        // つなぐ形式（44.1kHz・モノラル・Float32）と違うファイルは鳴らさない（形式違いの再生は落ちるため）。
        let f = buffer.format
        return f.sampleRate == format.sampleRate && f.channelCount == format.channelCount && f.commonFormat == format.commonFormat ? buffer : nil
    }
}
