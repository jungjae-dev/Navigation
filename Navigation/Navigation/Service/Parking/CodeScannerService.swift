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

    /// 인식 결과와 함께 **OCR이 처리한 원본 ARFrame**을 되돌려준다 —
    /// 콜백 시점의 currentFrame으로 역투영하면 이동 중 프레임 불일치 오차 발생 (PR#49 리뷰 M3/A-1)
    var onRecognitions: (([Recognition], ARFrame) -> Void)?

    private var isProcessing = false
    private var lastProcessedAt: TimeInterval = 0
    private let minInterval: TimeInterval = 1.0 / 3.0

    /// ARFrame을 백그라운드 Vision 처리로 넘기기 위한 래퍼 — 처리 중 1개만 유지(동시 1건 직렬화).
    /// nonisolated 명시: 기본 MainActor 격리가 적용되면 백그라운드 recognize에서 프로퍼티 접근 불가 (PR#49 리뷰)
    private nonisolated struct FrameBox: @unchecked Sendable {
        let frame: ARFrame
        let orientation: CGImagePropertyOrientation
    }

    /// 방향 상수 .right는 세로 고정 UI 전제 — ParkingARViewController의 역변환 수식과 한 쌍 (PR#49 리뷰 A-4)
    func process(frame: ARFrame, orientation: CGImagePropertyOrientation = .right) {
        guard !isProcessing, frame.timestamp - lastProcessedAt >= minInterval else { return }
        isProcessing = true
        lastProcessedAt = frame.timestamp

        let box = FrameBox(frame: frame, orientation: orientation)

        // MainActor 클로저를 값으로 만들어 detached로 전달 — 동시성 컨텍스트에서 self 캡처 변수 참조 금지 (PR#49 리뷰, Swift 6)
        let finish: @MainActor ([Recognition], FrameBox) -> Void = { [weak self] recognitions, box in
            self?.isProcessing = false
            self?.onRecognitions?(recognitions, box.frame)
        }
        Task.detached(priority: .userInitiated) {
            let recognitions = Self.recognize(box)
            await finish(recognitions, box)
        }
    }

    private nonisolated static func recognize(_ box: FrameBox) -> [Recognition] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false   // "B2-A-3"을 단어로 교정하려는 시도 차단

        let handler = VNImageRequestHandler(cvPixelBuffer: box.frame.capturedImage, orientation: box.orientation)
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
