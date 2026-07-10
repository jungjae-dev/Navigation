import Foundation
import Vision
import ARKit

/// ARFrame → Vision 텍스트 인식 (R2).
/// 3Hz 스로틀 + 동시 1건 — 발열·배터리 관리(NFR). 결과는 MainActor 콜백.
final class CodeScannerService {

    struct Recognition {
        let text: String
        let confidence: Float
        /// Vision 정규 좌표 (orientation 적용된 이미지 기준, 원점 좌하단)
        let boundingBox: CGRect
    }

    var onRecognitions: (([Recognition]) -> Void)?

    private var isProcessing = false
    private var lastProcessedAt: TimeInterval = 0
    private let minInterval: TimeInterval = 1.0 / 3.0

    /// CVPixelBuffer를 백그라운드 Vision 처리로 넘기기 위한 래퍼.
    /// ARKit이 프레임 버퍼를 재사용하지 않도록 참조만 유지 — 읽기 전용 접근.
    private struct FrameBox: @unchecked Sendable {
        let buffer: CVPixelBuffer
        let orientation: CGImagePropertyOrientation
    }

    func process(frame: ARFrame, orientation: CGImagePropertyOrientation = .right) {
        guard !isProcessing, frame.timestamp - lastProcessedAt >= minInterval else { return }
        isProcessing = true
        lastProcessedAt = frame.timestamp

        let box = FrameBox(buffer: frame.capturedImage, orientation: orientation)

        Task.detached(priority: .userInitiated) { [weak self] in
            let recognitions = Self.recognize(box)
            await MainActor.run {
                guard let self else { return }
                self.isProcessing = false
                self.onRecognitions?(recognitions)
            }
        }
    }

    private nonisolated static func recognize(_ box: FrameBox) -> [Recognition] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false   // "B2-A-3"을 단어로 교정하려는 시도 차단

        let handler = VNImageRequestHandler(cvPixelBuffer: box.buffer, orientation: box.orientation)
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Recognition(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}
