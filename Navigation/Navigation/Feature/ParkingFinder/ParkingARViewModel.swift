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
        var hits: Int
        var firstSeenAt: Date
        var lastSeenAt: Date
        /// 같은 코드의 관측 좌표를 표지판 인스턴스로 분리 보관 (FR-107).
        /// v2는 복수 위치를 "모호"로 보고 격자에서 통째로 뺐고, 그 결과 260919에서 '3'행이 전멸했다.
        var signs = SignInstanceSet()

        /// 층 확인·도착·디버그용 대표 좌표 — 가장 최근 인스턴스 (격자 선택과 무관)
        var position: SIMD2<Double>? { signs.mostRecentPosition }
        /// 다중 표지판 코드인가 (디버그 표시·로그용)
        var isMultiSign: Bool { signs.isMultiSign }
    }

    /// 저장 직전 층 확인이 필요한 보류 상태 (FR-005)
    struct PendingSave {
        let targetCode: String
    }

    /// 되찾기 안내 상태 — HUD는 이 상태의 순수 함수 (FR-010, UI 계약)
    enum GuidanceState: Equatable {
        case searching
        case needMore(message: String)
        /// distanceMeters는 표시 가능할 때만 non-nil (FR-106 — 낮은 확신에서 정밀해 보이는 숫자 금지)
        case guiding(stageLabel: String, arrowRadians: Double, distanceMeters: Double?, confidencePercent: Int)
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
    /// FR-103 히스테리시스용 직전 표시 백분율
    private var lastShownPercent: Int?
    /// 인스턴스 노화·리플레이 시간축 기준 (세션 시작 시각)
    private let sessionStartedAt = Date()

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
        lastShownPercent = nil
        // 좌표 무관 상태도 세션 단절과 함께 리셋 (PR#49 리뷰 M2):
        // neighborLogged가 남으면 estimator.reset() 후 인접 부스트가 영구 소실, 사진은 무관 기둥 레코드에 오귀속
        pendingFloorSave = nil
        neighborLogged.removeAll()
        floorReminderShown = false
        discardUnsavedPhotos()
        recorder?.observationsInvalidated()
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
            parsed: parsed, hits: 0, firstSeenAt: Date(), lastSeenAt: Date()
        )
        observation.hits += 1
        observation.lastSeenAt = Date()
        if let position {
            let before = observation.signs.instances.count
            observation.signs.add(position: SIMD2(Double(position.x), Double(position.z)),
                                  at: sessionSeconds())
            if observation.signs.instances.count > before, before > 0 {
                logger.info("[ParkingFinder] '\(key)' new sign instance #\(observation.signs.instances.count) (multi-sign lot)")
            }
        }
        observations[key] = observation
        return observation.hits == ParkingTuning.confirmHits
    }

    /// 세션 기준 경과 초 — 인스턴스 노화(FR-108)와 리플레이 시간축을 맞추기 위한 단조 시계
    private func sessionSeconds() -> Double {
        Date().timeIntervalSince(sessionStartedAt)
    }

    private func codeConfirmed(_ code: String) {
        logger.info("[ParkingFinder] accepted '\(code)' hit=\(ParkingTuning.confirmHits) → confirmed")
        confirmedCodes.send(confirmedCodes.value + [code])
        timeoutTask?.cancel()

        if photoPaths.count < ParkingTuning.maxAutoPhotos, let path = capturePhoto?() {
            photoPaths.append(path)
        }

        // pendingFloorSave 진행 중엔 재예약 불필요 — 층 응답(setManualFloor) 또는 취소가 흐름을 결정 (PR#49 리뷰 H1)
        guard case .scan = mode, saveTask == nil, pendingFloorSave == nil else { return }
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
            saveTask = nil   // 재무장 가능하게 — 시트가 응답 없이 사라져도 다음 확정 코드가 저장 흐름 재개 (PR#49 리뷰 H1)
            logger.info("[ParkingFinder] floor prompt shown (no floor token)")
            onNeedsFloorInput?(pending)
            return
        }

        finishSave(target: target, floorToken: target.parsed.floorToken, floorSource: .code)
    }

    /// 층 확인 시트 취소 — 대기 상태 해제, 다음 확정 코드에서 저장 흐름 재개 (PR#49 리뷰 H1)
    func cancelFloorInput() {
        pendingFloorSave = nil
        logger.info("[ParkingFinder] floor prompt cancelled")
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

    /// 레코드에 귀속되지 않은 자동 촬영 사진 삭제 — 미저장 이탈·세션 단절 시 고아 파일 방지 (PR#49 리뷰 B-1)
    func discardUnsavedPhotos() {
        guard !saved, !photoPaths.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for path in photoPaths {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(path))
        }
        logger.info("[ParkingFinder] discarded \(self.photoPaths.count) unsaved photo(s)")
        photoPaths.removeAll()
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
        // 격자 제외 규칙: 잘림 의심 — 다른 확정 코드의 진접두사(G25→"G2").
        // 다중 표지판은 더 이상 제외하지 않는다 — 인스턴스로 나눠 추정기가 조합을 고른다 (FR-107)
        let confirmedRaws = Set(
            observations.values.filter { $0.hits >= ParkingTuning.confirmHits }.map(\.parsed.raw)
        )
        let candidates = observations.values
            .filter { $0.hits >= ParkingTuning.confirmHits }
            .filter { observation in
                !confirmedRaws.contains { other in
                    other != observation.parsed.raw && other.hasPrefix(observation.parsed.raw)
                }
            }
            .compactMap { observation -> GridEstimator.GridCandidate? in
                guard observation.parsed.isGridUsable, !observation.signs.accepted.isEmpty else { return nil }
                return GridEstimator.GridCandidate(
                    codeRaw: observation.parsed.raw,
                    zoneIndex: observation.parsed.zoneIndex,
                    numberValue: observation.parsed.numberValue,
                    instances: observation.signs.accepted
                )
            }

        let estimate = estimator.estimate(
            candidates: candidates,
            targetZoneIndex: targetParsedCode?.zoneIndex,
            targetNumber: targetParsedCode?.numberValue,
            nowSeconds: sessionSeconds(),
            devicePosition: lastDevicePosition   // FR-107 동점 조합은 기기에 가까운 쪽
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
        if simd_length(f) > 1e-6 {
            lastDeviceForward = simd_normalize(f)   // 퇴화 시(폰을 아래로) 직전 방향 유지 — nil 고착 방지 (PR#49 리뷰 M5)
        }
        if let heading = lastDeviceForward {
            recorder?.devicePose(position: position, heading: heading)
        }
        // 포즈 틱마다 상태 재발행 — G3 거리 상한 등으로 내려간 안내가 걸어오면 복귀하도록 양방향 유지 (PR#49 리뷰 M5)
        if lastEstimate != nil {
            publishState(record: record)
        }
    }

    /// FR-110: 힌트(어디쯤인가)와 행동 지시(무엇을 비추면 좋아지는가)를 한 자리에서 함께 전달.
    /// 260919에서는 힌트가 존재하면 축 지시가 영영 표시되지 않아 사용자가 개선 방법을 알 수 없었다.
    private static func combined(hint: String?, action: String) -> String {
        guard let hint, !hint.isEmpty else { return action }
        return "\(hint)\n\(action)"
    }

    /// 보장 실패 원인별 행동 지시 — 원인을 단정하면 45m 떨어진 사용자에게 "거의 다 왔다"고 말하게 된다
    static func failureAction(_ failure: GuidanceGeometry.GuaranteeFailure?) -> String {
        switch failure {
        case .proximity:
            return "거의 다 온 것 같아요 — 주변 기둥 번호로 확인해보세요"
        case .beyondObservationSpan:
            return "아직 근거가 부족해요 — 가는 길의 기둥을 더 비춰주세요"
        case .uncertaintyTooLarge, .none:
            return "방향을 좁히는 중이에요 — 다른 기둥을 비춰주세요"
        }
    }

    /// FR-103 히스테리시스 — 구간 경계(실선/점선·거리 표시)에서 표시가 깜빡이지 않게 한다.
    /// 경계를 넘을 때만 값을 갱신하고, 경계 근방의 미세 진동은 직전 값을 유지한다.
    private func hysteresisAdjusted(_ percent: Int) -> Int {
        defer { lastShownPercent = percent }
        guard let previous = lastShownPercent else { return percent }
        let threshold = ParkingTuning.confidencePercentSolidThreshold
        let crossingUp = previous < threshold && percent >= threshold
        let crossingDown = previous >= threshold && percent < threshold
        if crossingUp || crossingDown,
           abs(percent - threshold) < ParkingTuning.confidencePercentHysteresis {
            return previous   // 경계에서 이력 폭 안쪽의 진동 — 직전 표시 유지
        }
        return percent
    }

    private func publishState(record: ParkingSessionRecord) {
        guard guidanceState.value != .arrived, let estimate = lastEstimate else { return }

        let newState: GuidanceState
        switch estimate.stage {
        case .searching:
            // 격자 불가 동안에도 확정 관측 기반 그라디언트 힌트로 안내 (위치 무관, 260911)
            newState = lastGradientMessage.map { .needMore(message: $0) } ?? .searching
        case .needMoreObservation(let missing):
            // FR-110: 그라디언트 힌트가 축 행동 지시를 가리지 않는다 — 둘을 함께 전달
            newState = .needMore(message: Self.combined(
                hint: lastGradientMessage,
                action: missing == .zone
                    ? "다른 구역의 기둥을 비춰주세요"
                    : "같은 구역의 다른 번호 기둥을 비춰주세요"
            ))
        case .degraded:
            newState = .degraded(targetCode: record.targetCodeRaw, hint: lastGradientMessage)
        case .axisGuidance, .gridGuidance:
            guard let target = cachedTargetPosition,
                  let devicePos = lastDevicePosition,
                  let forward = lastDeviceForward else {
                newState = .searching
                break
            }
            // FR-101: 측방 각도 보장이 성립할 때만 화살표. 무너지면 근접 모드로 넘긴다(FR-102)
            let geometry = GuidanceGeometry.evaluate(
                target: target,
                uncertainty: estimate.uncertainty,
                devicePosition: devicePos,
                deviceForward: forward,
                observationSpan: estimate.observationSpan,
                confidencePercent: estimate.confidencePercent
            )
            guard geometry.isDirectionGuaranteed else {
                // 보장 실패 원인을 단정하지 않는다 — 원거리 외삽을 "근접"이라 말하던 문제 (PR#59 리뷰)
                newState = .needMore(message: Self.combined(
                    hint: lastGradientMessage,
                    action: Self.failureAction(geometry.failure)
                ))
                break
            }
            let label = estimate.stage == .gridGuidance ? "격자 안내" : "축 안내"
            newState = .guiding(
                stageLabel: label,
                arrowRadians: geometry.arrowRadians,
                distanceMeters: geometry.isDistanceDisplayable ? geometry.distance : nil,
                confidencePercent: hysteresisAdjusted(geometry.displayPercent)
            )
        }

        logTransitionIfNeeded(to: newState)
        // FR-115: 화살표 상태뿐 아니라 모든 안내 상태를 기록 — 힌트가 실제 무엇을 표시했는지 로그에 남긴다
        let percent = lastEstimate?.confidencePercent
        let legacyConfidence = lastEstimate?.confidence.rawValue
        switch newState {
        case .guiding(_, let arrow, let distance, let shownPercent):
            recorder?.guidanceShown(state: lastStateKey, arrowDegrees: arrow * 180 / .pi,
                                    distanceMeters: distance, confidence: legacyConfidence,
                                    percent: shownPercent, message: nil)
        case .needMore(let message):
            recorder?.guidanceShown(state: lastStateKey, arrowDegrees: nil, distanceMeters: nil,
                                    confidence: legacyConfidence, percent: percent, message: message)
        case .degraded(_, let hint):
            recorder?.guidanceShown(state: lastStateKey, arrowDegrees: nil, distanceMeters: nil,
                                    confidence: legacyConfidence, percent: percent, message: hint)
        case .searching, .arrived:
            recorder?.guidanceShown(state: lastStateKey, arrowDegrees: nil, distanceMeters: nil,
                                    confidence: legacyConfidence, percent: percent, message: nil)
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
