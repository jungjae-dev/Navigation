import AVFoundation

/// TTS 음성 재생 (큐 방식 — 현재 안내 끝난 후 다음 재생)
final class VoiceTTSPlayer: NSObject {

    static let shared = VoiceTTSPlayer()

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [VoiceCommand] = []
    private(set) var isMuted = false

    // MARK: - Init

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            print("[VoiceTTS] Audio session error: \(error)")
        }
    }

    // MARK: - Public

    /// 음성 명령 큐에 추가
    func enqueue(_ command: VoiceCommand) {
        guard !isMuted else { return }
        queue.append(command)
        playNextIfIdle()
    }

    /// 음소거 토글
    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            synthesizer.stopSpeaking(at: .immediate)
            queue.removeAll()
        }
    }

    /// 음소거 설정
    func setMuted(_ muted: Bool) {
        isMuted = muted
        if isMuted {
            synthesizer.stopSpeaking(at: .immediate)
            queue.removeAll()
        }
    }

    /// 정지
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.removeAll()
    }

    // MARK: - Private

    private func playNextIfIdle() {
        guard !synthesizer.isSpeaking, let next = queue.first else { return }
        queue.removeFirst()

        let utterance = AVSpeechUtterance(string: next.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceTTSPlayer: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            playNextIfIdle()
        }
    }
}
