import Foundation
import Combine
import simd
import OSLog

private let logger = Logger(subsystem: "nav.parking", category: "ParkingFinder")

/// AR 화면(스캔/되찾기 공용)의 파이프라인 상태.
/// OCR 결과 → 파서 → 관측 누적 → (scan) 목표 선정·자동 저장 / (find) 격자 추정(US2).
/// raycast 등 뷰 의존 작업은 VC가 수행해 결과만 주입한다.
final class ParkingARViewModel {

    enum Mode {
        case scan
        case find(target: ParkingSessionRecord)
    }

    /// 확정(hit ≥ confirmHits)된 코드의 누적 관측
    struct Observation {
        let parsed: ParsedCode
        var position: simd_float3?   // nil = raycast 실패 관측 (층·도착 전용, FR-015)
        var hits: Int
        var firstSeenAt: Date
        var lastSeenAt: Date
    }

    /// 저장 직전 층 확인이 필요한 보류 상태 (FR-005)
    struct PendingSave {
        let targetCode: String
    }

    // MARK: - Outputs (상태)

    let mode: Mode
    /// 확정된 코드 목록 — 스캔 진행 칩·요약 화면 후보 목록
    let confirmedCodes = CurrentValueSubject<[String], Never>([])

    // MARK: - Outputs (이벤트 — VC 배선)

    var onNeedsFloorInput: ((PendingSave) -> Void)?
    var onSaved: ((ParkingSessionRecord) -> Void)?
    var onSuggestManualEntry: (() -> Void)?
    /// 코드 확정 순간의 프레임을 사진으로 저장 — VC 주입, 반환은 Documents 상대 경로
    var capturePhoto: (() -> String?)?

    // MARK: - Private

    private(set) var observations: [String: Observation] = [:]
    private var photoPaths: [String] = []
    private var saveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingFloorSave: PendingSave?
    private var saved = false

    init(mode: Mode) {
        self.mode = mode
    }

    // MARK: - Session lifecycle

    func sessionDidStart() {
        guard case .scan = mode, !saved else { return }
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ParkingTuning.scanTimeout))
            guard let self, !Task.isCancelled, self.confirmedCodes.value.isEmpty else { return }
            logger.info("[ParkingFinder] scan timeout — suggesting manual entry")
            self.onSuggestManualEntry?()
        }
    }

    /// 백그라운드 복귀 등 — 좌표는 세션 좌표계 종속이라 전부 무효화 (스펙 엣지)
    func invalidateObservations() {
        observations = [:]
        confirmedCodes.send([])
        saveTask?.cancel()
        saveTask = nil
        logger.info("[ParkingFinder] observations invalidated (session interrupted)")
    }

    // MARK: - Observation intake

    /// VC가 OCR 인식 + raycast 결과를 주입.
    /// - position: raycast 성공 시 세션 월드 좌표, 실패 시 nil
    func addRecognition(text: String, confidence: Float, position: simd_float3?) {
        guard !saved, confidence >= ParkingTuning.ocrMinConfidence else { return }
        guard let parsed = PillarCodeParser.parse(text) else { return }

        let key = parsed.raw
        var observation = observations[key] ?? Observation(
            parsed: parsed, position: nil, hits: 0, firstSeenAt: Date(), lastSeenAt: Date()
        )
        observation.hits += 1
        observation.lastSeenAt = Date()
        if let position {
            observation.position = position   // 재관측 시 최신 위치로 갱신 (FR-011 재앵커)
        }
        observations[key] = observation

        if observation.hits == ParkingTuning.confirmHits {
            codeConfirmed(key)
        }
    }

    private func codeConfirmed(_ code: String) {
        logger.info("[ParkingFinder] accepted '\(code)' hit=\(ParkingTuning.confirmHits) → confirmed")
        confirmedCodes.send(confirmedCodes.value + [code])
        timeoutTask?.cancel()

        if photoPaths.count < ParkingTuning.maxAutoPhotos, let path = capturePhoto?() {
            photoPaths.append(path)
        }

        guard case .scan = mode, saveTask == nil else { return }
        // 안정화 유예: 오인식 확정·최근접 선정을 위한 짧은 대기 — 인접 수집 대기가 아님 (FR-002)
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ParkingTuning.saveStabilization))
            guard let self, !Task.isCancelled else { return }
            self.attemptSave()
        }
    }

    // MARK: - Scan: 목표 선정 + 저장 (FR-002/002a/002b)

    private func attemptSave() {
        guard case .scan = mode, !saved else { return }
        let confirmed = observations.values.filter { $0.hits >= ParkingTuning.confirmHits }
        guard !confirmed.isEmpty else { return }

        let target = selectTarget(from: confirmed)

        if target.parsed.floorToken == nil, pendingFloorSave == nil {
            let pending = PendingSave(targetCode: target.parsed.raw)
            pendingFloorSave = pending
            logger.info("[ParkingFinder] floor prompt shown (no floor token)")
            onNeedsFloorInput?(pending)
            return
        }

        finishSave(target: target, floorToken: target.parsed.floorToken, floorSource: .code)
    }

    /// 층 확인 시트 응답 (FR-005). floorToken nil = "모름"
    func setManualFloor(_ floorToken: String?) {
        guard let _ = pendingFloorSave else { return }
        pendingFloorSave = nil
        let confirmed = observations.values.filter { $0.hits >= ParkingTuning.confirmHits }
        guard !confirmed.isEmpty else { return }
        let target = selectTarget(from: confirmed)
        finishSave(target: target, floorToken: floorToken, floorSource: .manual)
    }

    /// 스캔 시작 위치(원점=사용자) 최근접 — 전부 위치 실패 시 최다 관측 (FR-002a)
    private func selectTarget(from confirmed: [Observation]) -> Observation {
        let positioned = confirmed.filter { $0.position != nil }
        if !positioned.isEmpty {
            return positioned.min { simd_length($0.position!) < simd_length($1.position!) }!
        }
        return confirmed.max { ($0.hits, $0.firstSeenAt.timeIntervalSince1970 * -1)
            < ($1.hits, $1.firstSeenAt.timeIntervalSince1970 * -1) }!
    }

    private func finishSave(target: Observation, floorToken: String?, floorSource: ParkingSessionRecord.FloorSource) {
        saved = true

        let confirmed = observations.values.filter { $0.hits >= ParkingTuning.confirmHits }
        let neighbors: [NeighborCode] = confirmed
            .filter { $0.parsed.raw != target.parsed.raw }
            .map { observation in
                let distance: Double? = {
                    guard let t = target.position, let n = observation.position else { return nil }
                    return Double(simd_length(t - n))
                }()
                return NeighborCode(
                    codeRaw: observation.parsed.raw,
                    zoneToken: observation.parsed.zoneToken,
                    numberValue: observation.parsed.numberValue,
                    distanceToTarget: distance
                )
            }

        let skeleton = PillarCodeParser.skeleton(fromRegistered: confirmed.map(\.parsed))
        let record = ParkingSessionRecord(
            targetCodeRaw: target.parsed.raw,
            floorToken: floorToken,
            floorSource: floorSource,
            zoneToken: target.parsed.zoneToken,
            numberValue: target.parsed.numberValue,
            templateSkeleton: skeleton,
            photoPaths: photoPaths,
            neighbors: neighbors
        )
        DataService.shared.saveParkingSession(record)

        let neighborDesc = neighbors.map { n in
            "\(n.codeRaw)\(n.distanceToTarget.map { String(format: "(%.1fm)", $0) } ?? "")"
        }.joined(separator: ", ")
        logger.info("[ParkingFinder] scan: auto-saved target=\(record.targetCodeRaw) neighbors=[\(neighborDesc)] photos=\(record.photoPaths.count)")
        onSaved?(record)
    }

    /// 미저장 이탈 확인 필요 여부 (T020)
    var hasUnsavedInput: Bool {
        guard case .scan = mode else { return false }
        return !saved && !observations.isEmpty
    }

    func cancelTasks() {
        saveTask?.cancel()
        timeoutTask?.cancel()
    }
}
