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
        /// 좌표가 마지막으로 갱신된 시각 — 신선도 판정 기준 (드리프트 오염 방지, 260801 반영)
        var positionUpdatedAt: Date?
        /// 같은 코드가 멀리 떨어진 복수 표지판에서 관측됨(주차면 번호 반복 표기) —
        /// 좌표가 유일하지 않아 격자에서 제외, 층·도착 확인엔 계속 사용 (260911 반영)
        var isPositionAmbiguous = false
    }

    /// 저장 직전 층 확인이 필요한 보류 상태 (FR-005)
    struct PendingSave {
        let targetCode: String
    }

    /// 되찾기 안내 상태 — HUD는 이 상태의 순수 함수 (FR-010, UI 계약)
    enum GuidanceState: Equatable {
        case searching
        case needMore(message: String)
        case guiding(stageLabel: String, arrowRadians: Double, distanceMeters: Double, confidence: GridEstimate.Confidence)
        case degraded(targetCode: String, hint: String?)
        case arrived
    }

    /// 상태와 직교하는 배너 (data-model)
    enum Banner: Equatable {
        case floorMismatch(message: String)
        case trackingLimited
        case anchorFailing
    }

    // MARK: - Outputs (상태)

    let mode: Mode
    /// 확정된 코드 목록 — 스캔 진행 칩·요약 화면 후보 목록
    let confirmedCodes = CurrentValueSubject<[String], Never>([])
    let guidanceState = CurrentValueSubject<GuidanceState, Never>(.searching)
    let banner = CurrentValueSubject<Banner?, Never>(nil)
    /// DR-002 상태 스트립 텍스트 (디버그 활성 시에만 갱신)
    let debugStrip = CurrentValueSubject<String?, Never>(nil)

    /// 인식 1건의 처리 결과 — 디버그 인식 박스 색상·사유 (DR-001)
    enum RecognitionVerdict {
        case accepted(code: String)
        case rejected(reason: String)
        case ignored
        case arrivalProgress
    }

    /// NDJSON 레코더 (DR-003) — 디버그 토글 on일 때만 VC가 주입, off면 nil = 비용 0
    var recorder: ParkingEventRecorder?

    var isDebugEnabled: Bool {
        DevToolsSettings.shared.parkingDebugEnabled.value
    }

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

    // find 전용
    private var estimator = GridEstimator()
    private var arrivalTracker = ArrivalTracker()
    private var cachedTargetPosition: SIMD2<Double>?
    private var raycastFailStreak = 0
    private var lastStateKey = ""
    private(set) var lastEstimate: GridEstimate?   // 디버그 엔티티 갱신용 노출 (DR-001)
    private var lastDevicePosition: SIMD2<Double>?
    private var lastDeviceForward: SIMD2<Double>?
    private var neighborLogged: Set<String> = []
    private var floorReminderShown = false
    private let targetParsedCode: ParsedCode?
    private var gradientHint = NumberGradientHint()
    private var lastGradientMessage: String?

    init(mode: Mode) {
        self.mode = mode
        if case .find(let record) = mode {
            targetParsedCode = PillarCodeParser.parse(record.targetCodeRaw)
            if record.templateSkeleton == PillarCodeParser.rawSkeleton {
                // 파싱 불가 세션: 격자 안내 불가 — 근접확인 모드 고정 (FR-016, T034)
                guidanceState.send(.degraded(targetCode: record.targetCodeRaw, hint: nil))
            }
        } else {
            targetParsedCode = nil
        }
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
        estimator.reset()
        arrivalTracker.reset()
        cachedTargetPosition = nil
        lastEstimate = nil
        raycastFailStreak = 0
        gradientHint.reset()
        lastGradientMessage = nil
        if case .find(let record) = mode {
            if record.templateSkeleton == PillarCodeParser.rawSkeleton {
                guidanceState.send(.degraded(targetCode: record.targetCodeRaw, hint: nil))
            } else {
                guidanceState.send(.searching)
            }
        }
        logger.info("[ParkingFinder] observations invalidated (session interrupted)")
    }

    // MARK: - Observation intake

    /// VC가 OCR 인식 + raycast 결과를 주입. 반환 verdict는 디버그 인식 박스용 (DR-001).
    /// - position: raycast 성공 시 세션 월드 좌표, 실패 시 nil
    @discardableResult
    func addRecognition(text: String, confidence: Float, position: simd_float3?, positionSource: String? = nil) -> RecognitionVerdict {
        guard confidence >= ParkingTuning.ocrMinConfidence else {
            recorder?.candidateRejected(raw: text, reason: "low-conf")
            return .rejected(reason: "low-conf")
        }

        switch mode {
        case .scan:
            return handleScanRecognition(text: text, confidence: confidence, position: position, source: positionSource)
        case .find(let record):
            return handleFindRecognition(text: text, confidence: confidence, position: position, source: positionSource, record: record)
        }
    }

    private func handleScanRecognition(text: String, confidence: Float, position: simd_float3?, source: String?) -> RecognitionVerdict {
        guard !saved else { return .ignored }
        guard let parsed = PillarCodeParser.parse(text) else { return .ignored }

        let confirmed = upsertObservation(parsed, position: position)
        recorder?.codeObserved(
            raw: parsed.raw, parsed: parsed, position: position,
            confidence: confidence, hit: observations[parsed.raw]?.hits ?? 0, source: source
        )
        if confirmed {
            codeConfirmed(parsed.raw)
        }
        return .accepted(code: parsed.raw)
    }

    /// 관측 누적 — 확정 순간(hit == confirmHits)이면 true (FR-011 재앵커 포함)
    @discardableResult
    private func upsertObservation(_ parsed: ParsedCode, position: simd_float3?) -> Bool {
        let key = parsed.raw
        var observation = observations[key] ?? Observation(
            parsed: parsed, position: nil, hits: 0, firstSeenAt: Date(), lastSeenAt: Date(),
            positionUpdatedAt: nil
        )
        observation.hits += 1
        observation.lastSeenAt = Date()
        if let position {
            if let existing = observation.position, !observation.isPositionAmbiguous,
               simd_length(position - existing) > ParkingTuning.sameCodeJumpThreshold {
                observation.isPositionAmbiguous = true
                logger.info("[ParkingFinder] '\(key)' position jump \(String(format: "%.1f", simd_length(position - existing)))m → ambiguous (multi-sign), excluded from grid")
            } else if !observation.isPositionAmbiguous {
                observation.position = position   // 재관측 시 최신 위치로 갱신
                observation.positionUpdatedAt = Date()
            }
        }
        observations[key] = observation
        return observation.hits == ParkingTuning.confirmHits
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
        let skeleton = PillarCodeParser.skeleton(fromRegistered: confirmed.map(\.parsed))
        // 인접 저장은 대표 스켈레톤 일치만 — 구역 잘린 부분 인식("J23"→"23")이 인접으로 남는 것 방지 (260911)
        let neighbors: [NeighborCode] = confirmed
            .filter { $0.parsed.raw != target.parsed.raw && $0.parsed.skeleton == skeleton }
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

    // MARK: - Find: 되찾기 파이프라인 (T024/T027, FR-008~016)

    private func handleFindRecognition(
        text: String, confidence: Float, position: simd_float3?, source: String?, record: ParkingSessionRecord
    ) -> RecognitionVerdict {
        guard guidanceState.value != .arrived else { return .ignored }

        // 도착 판정 — 위치·파싱 성공 여부와 무관 (FR-013/015).
        // 원문 일치 + 파싱 동치 이중화: "09"/"9" 표기 흔들림·선행 0 구버전 기록 대응 (260712 현장 로그)
        let normalized = PillarCodeParser.normalized(text)
        let isTargetMatch: Bool = {
            if normalized == record.targetCodeRaw { return true }
            guard let parsed = PillarCodeParser.parse(text), let target = targetParsedCode,
                  target.zoneToken != nil || target.numberValue != nil else { return false }
            let floorCompatible = parsed.floorToken == nil || target.floorToken == nil
                || parsed.floorToken == target.floorToken
            return parsed.zoneToken == target.zoneToken
                && parsed.numberValue == target.numberValue
                && floorCompatible
        }()
        if isTargetMatch {
            if arrivalTracker.registerTargetSighting() {
                logState(to: "arrived", trigger: "target \(ParkingTuning.arrivalConsecutive) consecutive")
                guidanceState.send(.arrived)
                recorder?.sessionEnd(by: "target-recognition")
            }
            return .arrivalProgress
        }

        guard let parsed = PillarCodeParser.parse(text) else { return .ignored }

        // 오검출 필터 — 등록 템플릿 구조 일치만 채택 (FR-008)
        guard PillarCodeParser.matchesTemplate(parsed, skeleton: record.templateSkeleton) else {
            logger.info("[ParkingFinder] rejected '\(parsed.raw)' reason=skeleton-mismatch")
            recorder?.candidateRejected(raw: parsed.raw, reason: "skeleton-mismatch")
            return .rejected(reason: "skeleton-mismatch")
        }

        // 층 확인 (FR-014) — 다른 층 관측은 격자 오염 방지 위해 제외
        if let candidateFloor = parsed.floorToken, let recordFloor = record.floorToken,
           candidateFloor != recordFloor {
            banner.send(.floorMismatch(message: "여기는 \(candidateFloor) — \(recordFloor)로 이동하세요"))
            logger.info("[ParkingFinder] floor mismatch: seen=\(candidateFloor) target=\(recordFloor)")
            recorder?.candidateRejected(raw: parsed.raw, reason: "floor-mismatch")
            return .rejected(reason: "floor-mismatch")
        }
        if parsed.floorToken == nil, let recordFloor = record.floorToken,
           record.floorSource == .manual, !floorReminderShown {
            floorReminderShown = true
            banner.send(.floorMismatch(message: "\(recordFloor)에 주차하셨습니다"))
        }

        // 저장 인접 코드 목격 → 근접 신호 (FR-013a)
        if record.neighbors.contains(where: { $0.codeRaw == parsed.raw }),
           !neighborLogged.contains(parsed.raw) {
            neighborLogged.insert(parsed.raw)
            estimator.markNeighborSighted()
            logger.info("[ParkingFinder] neighbor sighted: \(parsed.raw) → confidence boost")
        }

        // 위치 파악 실패 관측: 층·도착 확인엔 이미 사용됨, 격자엔 미포함 (FR-015)
        if position == nil {
            raycastFailStreak += 1
            recorder?.raycastFailed(raw: parsed.raw, consecutive: raycastFailStreak)
            if raycastFailStreak >= ParkingTuning.raycastFailBannerAfter {
                banner.send(.anchorFailing)
            }
        } else {
            raycastFailStreak = 0
        }

        if upsertObservation(parsed, position: position) {
            confirmedCodes.send(confirmedCodes.value + [parsed.raw])
        }
        recorder?.codeObserved(
            raw: parsed.raw, parsed: parsed, position: position,
            confidence: confidence, hit: observations[parsed.raw]?.hits ?? 0, source: source
        )

        // 그라디언트 힌트 갱신 (FR-012) — 위치 무관: 격자가 못 서는 동안에도 구역·번호로 안내 (260911)
        if let target = targetParsedCode,
           (observations[parsed.raw]?.hits ?? 0) >= ParkingTuning.confirmHits,
           let message = gradientHint.hint(target: target, observed: parsed) {
            lastGradientMessage = message
        }

        // 파싱 불가 세션은 근접확인 모드 고정 — 격자 추정 생략 (FR-016)
        guard record.templateSkeleton != PillarCodeParser.rawSkeleton else {
            return .accepted(code: parsed.raw)
        }
        runEstimate(record: record)
        return .accepted(code: parsed.raw)
    }

    private func runEstimate(record: ParkingSessionRecord) {
        // 격자 제외 규칙 (260911): ① 다중 표지판 모호 코드 ② 잘림 의심 — 다른 확정 코드의 진접두사(G25→"G2")
        let confirmedRaws = Set(
            observations.values.filter { $0.hits >= ParkingTuning.confirmHits }.map(\.parsed.raw)
        )
        let gridObservations = observations.values
            .filter { $0.hits >= ParkingTuning.confirmHits && !$0.isPositionAmbiguous }
            .filter { observation in
                !confirmedRaws.contains { other in
                    other != observation.parsed.raw && other.hasPrefix(observation.parsed.raw)
                }
            }
            .compactMap { observation -> GridObservation? in
                guard let p = observation.position, observation.parsed.isGridUsable else { return nil }
                return GridObservation(
                    codeRaw: observation.parsed.raw,
                    zoneIndex: observation.parsed.zoneIndex,
                    numberValue: observation.parsed.numberValue,
                    position: SIMD2(Double(p.x), Double(p.z)),
                    ageSeconds: observation.positionUpdatedAt.map { Date().timeIntervalSince($0) } ?? 0
                )
            }

        let estimate = estimator.estimate(
            observations: gridObservations,
            targetZoneIndex: targetParsedCode?.zoneIndex,
            targetNumber: targetParsedCode?.numberValue
        )
        lastEstimate = estimate
        cachedTargetPosition = estimate.targetPosition
        logger.info("[ParkingFinder] grid updated: stage=\(String(describing: estimate.stage)) obs=\(estimate.observationCount) residual=\(String(format: "%.1f", estimate.residualRMS))m conf=\(estimate.confidence.rawValue)")
        recorder?.gridUpdated(estimate)
        updateDebugStrip(estimate)
        publishState(record: record)
    }

    /// DR-002 상태 스트립 — 디버그 활성 시에만 갱신
    private func updateDebugStrip(_ estimate: GridEstimate) {
        guard isDebugEnabled else { return }
        let valid = observations.values.filter { $0.hits >= ParkingTuning.confirmHits && $0.position != nil }.count
        debugStrip.send(String(
            format: "%@ · 관측 %d(유효 %d) · 잔차 %.1fm · 신뢰 %d",
            lastStateKey, observations.count, valid, estimate.residualRMS, estimate.confidence.rawValue
        ))
    }

    /// 트래킹 품질 저하 보고 (FR-015 — VC delegate에서 호출)
    func reportTrackingLimited() {
        banner.send(.trackingLimited)
    }

    /// VC가 프레임마다(스로틀) 호출 — 화살표는 기기 포즈의 함수 (data-model DeviceContext)
    func updateDevicePose(position: simd_float3, forward: simd_float3) {
        guard case .find(let record) = mode else { return }
        lastDevicePosition = SIMD2(Double(position.x), Double(position.z))
        let f = SIMD2(Double(forward.x), Double(forward.z))
        lastDeviceForward = simd_length(f) > 1e-6 ? simd_normalize(f) : nil
        if let heading = lastDeviceForward {
            recorder?.devicePose(position: position, heading: heading)
        }
        if case .guiding = guidanceState.value {
            publishState(record: record)
        }
    }

    private func publishState(record: ParkingSessionRecord) {
        guard guidanceState.value != .arrived, let estimate = lastEstimate else { return }

        let newState: GuidanceState
        switch estimate.stage {
        case .searching:
            // 격자 불가 동안에도 확정 관측 기반 그라디언트 힌트로 안내 (위치 무관, 260911)
            newState = lastGradientMessage.map { .needMore(message: $0) } ?? .searching
        case .needMoreObservation(let missing):
            let axisMessage = missing == .zone
                ? "다른 구역의 기둥을 비춰주세요"
                : "같은 구역의 다른 번호 기둥을 비춰주세요"
            newState = .needMore(message: lastGradientMessage ?? axisMessage)
        case .degraded:
            newState = .degraded(targetCode: record.targetCodeRaw, hint: lastGradientMessage)
        case .axisGuidance, .gridGuidance:
            guard let target = cachedTargetPosition,
                  let devicePos = lastDevicePosition,
                  let forward = lastDeviceForward else {
                newState = .searching
                break
            }
            let toTarget = target - devicePos
            let distance = simd_length(toTarget)
            let direction = distance > 1e-6 ? toTarget / distance : forward
            // 부호 규약: 전방 기준 시계방향(+) — 화면 회전값으로 직접 사용. 현장 검증(D2) 대상
            let arrow = atan2(
                forward.x * direction.y - forward.y * direction.x,
                simd_dot(forward, direction)
            )
            let label = estimate.stage == .gridGuidance ? "격자 안내" : "축 안내"
            newState = .guiding(
                stageLabel: label,
                arrowRadians: arrow,
                distanceMeters: distance,
                confidence: estimate.confidence
            )
        }

        logTransitionIfNeeded(to: newState)
        if case .guiding(_, let arrow, let distance, let conf) = newState {
            recorder?.guidanceShown(
                state: lastStateKey,
                arrowDegrees: arrow * 180 / .pi,
                distanceMeters: distance,
                confidence: conf.rawValue
            )
        }
        if newState != guidanceState.value {
            guidanceState.send(newState)
        }
    }

    private func logTransitionIfNeeded(to state: GuidanceState) {
        let key: String
        switch state {
        case .searching: key = "searching"
        case .needMore: key = "needMore"
        case .guiding(let label, _, _, _): key = label
        case .degraded: key = "degraded"
        case .arrived: key = "arrived"
        }
        if key != lastStateKey {
            logState(to: key, trigger: "obs=\(lastEstimate?.observationCount ?? 0)")
        }
    }

    private func logState(to key: String, trigger: String) {
        logger.info("[ParkingFinder] state: \(self.lastStateKey.isEmpty ? "-" : self.lastStateKey) → \(key) (\(trigger))")
        recorder?.stateTransition(from: lastStateKey.isEmpty ? "-" : lastStateKey, to: key, trigger: trigger)
        lastStateKey = key
    }
}
