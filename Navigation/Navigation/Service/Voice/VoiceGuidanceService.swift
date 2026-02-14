import Foundation
import AVFoundation
import Combine

final class VoiceGuidanceService: NSObject {

    // MARK: - Publishers

    let isSpeakingPublisher = CurrentValueSubject<Bool, Never>(false)
    let isMutedPublisher = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ko-KR")

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Public

    func speak(_ text: String) {
        guard !isMutedPublisher.value else { return }

        // Stop current speech and speak new text
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = createUtterance(text)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func toggleMute() {
        let newValue = !isMutedPublisher.value
        isMutedPublisher.send(newValue)

        if newValue {
            stop()
        }
    }

    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            print("⚠️ Audio session configuration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func createUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.50
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        return utterance
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceGuidanceService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            isSpeakingPublisher.send(true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            isSpeakingPublisher.send(false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            isSpeakingPublisher.send(false)
        }
    }
}
