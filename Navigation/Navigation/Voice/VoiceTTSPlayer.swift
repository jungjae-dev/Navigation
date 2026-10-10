import AVFoundation

/// TTS 음성 재생 (큐 방식 — 현재 안내 끝난 후 다음 재생)
final class VoiceTTSPlayer: NSObject {

    static let shared = VoiceTTSPlayer()

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [VoiceCommand] = []
    private(set) var isMuted = false
    /// 오디오 세션은 재생 직전에만 켜고 큐가 비면 끈다 — 세션이 살아 있는 동안 타 앱 음악이 덕킹되므로
    private var isAudioSessionActive = false

    // MARK: - Init

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Audio Session

    private func activateAudioSession() {
        guard !isAudioSessionActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            isAudioSessionActive = true
        } catch {
            print("[VoiceTTS] Audio session error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        guard isAudioSessionActive else { return }
        isAudioSessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[VoiceTTS] Audio session deactivate error: \(error)")
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
        setMuted(!isMuted)
    }

    /// 음소거 설정
    func setMuted(_ muted: Bool) {
        isMuted = muted
        if isMuted { stop() }
    }

    /// 정지
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.removeAll()
        deactivateAudioSession()
    }

    // MARK: - Private

    private func playNextIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        guard let next = queue.first else {
            deactivateAudioSession()
            return
        }
        queue.removeFirst()
        activateAudioSession()

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
