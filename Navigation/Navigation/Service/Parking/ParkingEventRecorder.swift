import Foundation
import simd
import UIKit
import ARKit
import OSLog

private let logger = Logger(subsystem: "nav.parking", category: "ParkingFinder")

/// 관측 이벤트 NDJSON 레코더 (DR-003, contracts/parking-observation-log.md).
/// 디버그 토글 off면 인스턴스 자체가 생성되지 않아 비용 0 (DR-005).
/// 카메라 영상·이미지는 기록하지 않는다 — 추정 로직 계층 리플레이용 이벤트만.
final class ParkingEventRecorder {

    private let fileURL: URL
    private var handle: FileHandle?
    private let sessionStartedAt = Date()
    private var lastPoseLoggedAt: Date = .distantPast
    private var lastGuidanceLoggedAt: Date = .distantPast

    init?(mode: String, target: ParkingSessionRecord?) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ParkingLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "parking-\(formatter.string(from: sessionStartedAt))-\(mode).ndjson"
        fileURL = dir.appendingPathComponent(name)

        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil),
              let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
            return nil
        }
        handle = fileHandle

        var payload: [String: Any] = [
            "mode": mode,
            "device": UIDevice.current.model,
            "lidar": ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
        ]
        if let target {
            payload["target"] = [
                "raw": target.targetCodeRaw,
                "floor": target.floorToken as Any,
                "skeleton": target.templateSkeleton,
            ]
            payload["neighbors"] = target.neighbors.map(\.codeRaw)
        }
        write(event: "sessionStart", payload)
        logger.info("[ParkingFinder] recording to \(name)")
    }

    deinit {
        try? handle?.close()
    }

    // MARK: - Events (스키마: contracts/parking-observation-log.md)

    func codeObserved(raw: String, parsed: ParsedCode?, position: simd_float3?, confidence: Float, hit: Int, source: String? = nil) {
        var payload: [String: Any] = ["raw": raw, "conf": round3(Double(confidence)), "hit": hit]
        if let source { payload["src"] = source }   // raycast/depth — 폴백 효과 측정용
        if let parsed {
            payload["parsed"] = [
                "floor": parsed.floorToken as Any,
                "zone": parsed.zoneToken as Any,
                "zoneIdx": parsed.zoneIndex as Any,
                "num": parsed.numberValue as Any,
            ]
        }
        payload["pos"] = position.map { [round3(Double($0.x)), round3(Double($0.y)), round3(Double($0.z))] } ?? NSNull()
        write(event: "codeObserved", payload)
    }

    func candidateRejected(raw: String, reason: String) {
        write(event: "candidateRejected", ["raw": raw, "reason": reason])
    }

    func raycastFailed(raw: String, consecutive: Int) {
        write(event: "raycastFailed", ["raw": raw, "consecutive": consecutive])
    }

    func trackingChanged(state: String, reason: String? = nil) {
        write(event: "trackingChanged", ["state": state, "reason": reason as Any])
    }

    /// 1Hz 스로틀 — 고빈도 데이터는 콘솔 대신 여기만 (quickstart 로그 설계)
    func devicePose(position: simd_float3, heading: SIMD2<Double>) {
        let now = Date()
        guard now.timeIntervalSince(lastPoseLoggedAt) >= 1.0 else { return }
        lastPoseLoggedAt = now
        write(event: "devicePose", [
            "pos": [round3(Double(position.x)), round3(Double(position.y)), round3(Double(position.z))],
            "heading": [round3(heading.x), round3(heading.y)],
        ])
    }

    func gridUpdated(_ estimate: GridEstimate) {
        write(event: "gridUpdated", [
            "stage": String(describing: estimate.stage),
            "obs": estimate.observationCount,
            "residualRMS": round3(estimate.residualRMS),
            "targetEst": estimate.targetPosition.map { [round3($0.x), round3($0.y)] } ?? NSNull(),
            "origin": estimate.origin.map { [round3($0.x), round3($0.y)] } ?? NSNull(),
            "zoneVec": estimate.zoneVec.map { [round3($0.x), round3($0.y)] } ?? NSNull(),
            "numVec": estimate.numVec.map { [round3($0.x), round3($0.y)] } ?? NSNull(),
            "confidence": estimate.confidence.rawValue,   // 구 3단계 — 기존 로그·도구 호환 (FR-115)
            "lever": estimate.extrapolationLever.map(round3) as Any,
            // v3 (spec 006): 연속 백분율과 측방 불확실성 성분 — 튜닝·리플레이 대조용
            "conf%": estimate.confidencePercent,
            "uncU": round3(estimate.uncertainty.unknownAxis),
            "uncFit": round3(estimate.uncertainty.fit),
            "uncExp": round3(estimate.uncertainty.expansion),
            "span": round3(estimate.observationSpan),
        ])
    }

    /// FR-115: 모든 안내 상태를 기록. `confidence`(구 3단계)는 호환용으로 유지하고 `conf%`·`msg`를 병행 —
    /// 260919 분석에서 "무엇이 표시됐는지"를 코드 추론에 의존해야 했던 공백을 메운다.
    func guidanceShown(
        state: String,
        arrowDegrees: Double?,
        distanceMeters: Double?,
        confidence: Int?,
        percent: Int? = nil,
        message: String? = nil
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastGuidanceLoggedAt) >= 1.0 else { return }
        lastGuidanceLoggedAt = now
        write(event: "guidanceShown", [
            "state": state,
            "arrowDeg": arrowDegrees.map(round3) as Any,
            "distanceM": distanceMeters.map(round3) as Any,
            "confidence": confidence as Any,
            "conf%": percent as Any,
            "msg": message as Any,
        ])
    }

    func stateTransition(from: String, to: String, trigger: String) {
        write(event: "stateTransition", ["from": from, "to": to, "trigger": trigger])
    }

    /// 세션 중단으로 관측 전체 무효화 — 리플레이어가 동일 시점에 상태를 리셋하기 위한 이벤트 (PR#49 리뷰 L8)
    func observationsInvalidated() {
        write(event: "observationsInvalidated", [:])
    }

    func sessionEnd(by trigger: String) {
        write(event: "sessionEnd", ["by": trigger, "elapsed": round3(Date().timeIntervalSince(sessionStartedAt))])
        try? handle?.close()
        handle = nil
    }

    // MARK: - Private

    private func write(event: String, _ payload: [String: Any]) {
        guard let handle else { return }
        var object = payload
        object["t"] = round3(Date().timeIntervalSince(sessionStartedAt))
        object["e"] = event
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }

    private func round3(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
