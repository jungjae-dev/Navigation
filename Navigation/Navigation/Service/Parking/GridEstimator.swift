import Foundation
import simd

/// 격자 추정 입력 관측 — 수평면(xz) 투영 좌표 + 파싱 인덱스 (data-model)
struct GridObservation: Equatable, Sendable {
    let codeRaw: String
    let zoneIndex: Int?
    let numberValue: Int?
    let position: SIMD2<Double>
    /// 마지막 재관측 이후 경과(s) — 임계 초과 시 격자에서 제외 (드리프트 오염 방지)
    var ageSeconds: Double = 0
}

/// 단계적 격자 추정 결과
struct GridEstimate: Equatable, Sendable {

    enum Stage: Equatable, Sendable {
        case searching                                    // 유효 관측 < 2
        case needMoreObservation(missing: Axis)           // 혼합축 2개 / 축 확보했으나 목표가 축 밖
        case axisGuidance(axis: Axis)                     // 1D 외삽
        case gridGuidance                                 // 2D 아핀
        case degraded                                     // 모순 감지 — 근접확인 모드 (FR-012)
    }

    enum Axis: Equatable, Sendable {
        case zone     // 구역축 부족 → "다른 구역 기둥을 비춰주세요"
        case number   // 번호축 부족 → "같은 구역의 다른 번호 기둥을 비춰주세요"
    }

    enum Confidence: Int, Comparable, Equatable, Sendable {
        case low = 0, medium = 1, high = 2
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// 목표 점추정의 측방 불확실성 (FR-101) — 화살표 표시 보장의 입력.
    /// 세 성분을 분리해 두는 이유: 사용자 안내 문구(무엇을 비추면 줄어드는가)와 디버그가 성분별로 달라진다.
    struct Uncertainty: Equatable, Sendable {
        /// 미지 축 오프셋 — 목표가 관측된 축 밖일 때 (스텝 수 × 축 피치). 대칭이므로 점추정은 이동하지 않는다
        var unknownAxis: Double = 0
        /// 적합·외삽 불확실성 — 잔차×레버 + 스텝당 모델 오차×외삽 스텝. 두 축이 성립해도 0이 아니다
        var fit: Double = 0
        /// 관측 노화 팽창 (FR-108)
        var expansion: Double = 0

        /// 등방 근사 반경(m) — 보수적으로 합산
        var radius: Double { unknownAxis + fit + expansion }
    }

    let stage: Stage
    /// 목표 외삽 위치 (xz) — axisGuidance/gridGuidance에서만 non-nil
    let targetPosition: SIMD2<Double>?
    let residualRMS: Double
    let confidence: Confidence
    let observationCount: Int
    /// FR-103 표시 백분율 (5~95) — 연속 점수. confidence 3단계는 구 로그·도구 호환용으로 병존
    var confidencePercent: Int = 0
    var uncertainty: Uncertainty = .init()
    /// FR-106 기준량 — 랜드마크 간 최대 이격(m). 기기 경로는 포함하지 않는다
    var observationSpan: Double = 0
    /// 디버그 시각화용 피팅 모델 (DR-001) — 관측 인덱스의 예측 위치 재계산에 사용
    var origin: SIMD2<Double>? = nil
    var zoneVec: SIMD2<Double>? = nil
    var numVec: SIMD2<Double>? = nil
    /// G1 외삽 레버 √(aᵀM⁻¹a) — 관측 배치 대비 목표 외삽 정도 (튜닝·로그용, 설계 개정 v2)
    var extrapolationLever: Double? = nil

    /// 피팅 모델로 관측 인덱스의 예측 위치 계산 — 잔차선·고스트 격자점 (DR-001)
    func predictedPosition(zoneIndex: Int?, number: Int?) -> SIMD2<Double>? {
        guard let origin else { return nil }
        var position = origin
        if let zi = zoneIndex, let zv = zoneVec { position += Double(zi) * zv }
        if let n = number, let nv = numVec { position += Double(n) * nv }
        return position
    }
}

/// 도착 확정 조건 — 일시적 오인식 1회로 확정 금지 (FR-013).
/// 최소 간격을 둔 연속 인식이 arrivalConsecutive회 누적되면 도착.
struct ArrivalTracker: Sendable {

    private var lastSightingAt: Date?
    private var count = 0

    mutating func registerTargetSighting(at date: Date = Date()) -> Bool {
        if let last = lastSightingAt {
            if date.timeIntervalSince(last) >= ParkingTuning.arrivalMinInterval {
                count += 1
                lastSightingAt = date
            }
            // 간격 미달 인식은 같은 순간으로 간주 — 시각만 유지
        } else {
            count = 1
            lastSightingAt = date
        }
        return count >= ParkingTuning.arrivalConsecutive
    }

    mutating func reset() {
        lastSightingAt = nil
        count = 0
    }
}

/// 단계적 격자 추정 + 잔차 기반 모순 감지 상태 기계 (R5, FR-009/012).
/// 순수 계산 — 같은 관측 시퀀스는 같은 결과 (리플레이 계약, SC-009).
struct GridEstimator: Sendable {

    private(set) var isDegraded = false
    private var consistentCount = 0
    /// 저장된 인접 코드 목격 → 신뢰도 상승 (FR-013a)
    private(set) var neighborSighted = false

    /// 이번 추정 회차의 파생량 (makeResult가 읽는다) — 순수 함수성 유지를 위해 estimate 진입 시 매번 재계산
    private var expansion: Double = 0
    private var span: Double = 0
    private var referencePitch: Double = 0

    /// 세션 중 실제로 추정된 적 있는 축 피치 (FR-101) — 미지 축 불확실성에 정적 사전값보다 우선 사용.
    /// 2D로 두 축을 학습한 뒤 관측 하나가 필터로 빠져 1D로 내려갈 때, 방금 학습한 값을 버리지 않기 위함.
    private var observedZonePitch: Double?
    private var observedNumberPitch: Double?

    // MARK: - Update

    mutating func markNeighborSighted() {
        neighborSighted = true
    }

    /// 관측 전체 무효화 후 재시작 (백그라운드 복귀)
    mutating func reset() {
        isDegraded = false
        consistentCount = 0
        neighborSighted = false
        observedZonePitch = nil
        observedNumberPitch = nil
    }

    /// 누적 관측 전체로 재추정 (매 관측 갱신마다 호출 — FR-011)
    mutating func estimate(
        observations: [GridObservation],
        targetZoneIndex: Int?,
        targetNumber: Int?
    ) -> GridEstimate {
        // v3(FR-108): 오래된 관측을 제외하지 않는다 — 제외는 260919에서 관측 전멸을 낳았다.
        // 대신 노화를 불확실성 팽창으로 흡수하고 점추정에는 손대지 않는다.
        let usable = observations
        expansion = Self.expansion(of: usable)
        span = Self.span(of: usable)
        referencePitch = 0

        guard usable.count >= 2 else {
            return makeResult(stage: .searching, target: nil, residual: 0, count: usable.count)
        }

        // 2D 아핀 시도 (비공선 3개 이상) → 실패 시 1D 축으로 단계 하강
        if usable.count >= 3,
           let (affine, normalMatrix) = fitAffine(usable) {
            referencePitch = affine.spacingEstimate
            // 두 축을 실제로 추정했으므로 세션 값으로 기억 (FR-101 — 1D로 내려가도 재사용)
            observedZonePitch = simd_length(affine.zoneVec)
            observedNumberPitch = simd_length(affine.numVec)
            let residual = affine.residualRMS(over: usable)
            // 잔차는 4점부터만 의미(3점=정확결정계, 잔차 항등 0 — 설계 개정 v2)
            let residualInformative = usable.count >= ParkingTuning.residualInformativeMinCountAffine
            if residualInformative {
                updateDegradation(residual: residual, spacing: affine.spacingEstimate)
            }

            if isDegraded {
                return makeResult(stage: .degraded, target: nil, residual: residual, count: usable.count,
                                  residualInformative: residualInformative)
            }
            guard let zi = targetZoneIndex, let n = targetNumber else {
                // 목표 인덱스 불완전(파싱 불가 세션은 상류에서 차단) — 방어적 강등
                return makeResult(stage: .degraded, target: nil, residual: residual, count: usable.count,
                                  residualInformative: residualInformative)
            }

            // FR-105 위생 검사 — 명백한 부조리만 차단(정상 16.9m/스텝을 기각하던 좁은 상한 폐기)
            if Self.stepAbsurd(affine.zoneVec) {
                return makeResult(stage: .needMoreObservation(missing: .zone), target: nil,
                                  residual: residual, count: usable.count,
                                  residualInformative: residualInformative)
            }
            if Self.stepAbsurd(affine.numVec) {
                return makeResult(stage: .needMoreObservation(missing: .number), target: nil,
                                  residual: residual, count: usable.count,
                                  residualInformative: residualInformative)
            }

            // FR-101: 레버는 차단 기준이 아니라 측방 불확실성의 성분이다.
            // 잔차×레버만으로는 부족하다(J21은 잔차 0.10m라 0.7m로 과소평가) — 정확결정계에서도 0이 되지
            // 않도록 바닥을 둔다. 배치 대비 외삽 위험은 스팬 상대 기준(GuidanceGeometry)이 맡는다.
            let lever = Self.affineLever(normalMatrix, targetZone: zi, targetNumber: n)
            let fitUncertainty = max(ParkingTuning.fitUncertaintyFloor, residual * (lever ?? 1.0))

            let target = affine.predict(zoneIndex: zi, number: n)
            return makeResult(stage: .gridGuidance, target: target, residual: residual, count: usable.count,
                              origin: affine.origin, zoneVec: affine.zoneVec, numVec: affine.numVec,
                              residualInformative: residualInformative, lever: lever,
                              uncertainty: .init(unknownAxis: 0, fit: fitUncertainty, expansion: expansion),
                              stepNormal: Self.stepNormal(affine.zoneVec) && Self.stepNormal(affine.numVec))
        }

        return estimate1D(usable, targetZoneIndex: targetZoneIndex, targetNumber: targetNumber)
    }

    // MARK: - 1D (관측 2개 또는 아핀 퇴화)

    private mutating func estimate1D(
        _ usable: [GridObservation],
        targetZoneIndex: Int?,
        targetNumber: Int?
    ) -> GridEstimate {
        let zones = Set(usable.compactMap(\.zoneIndex))
        let numbers = Set(usable.compactMap(\.numberValue))

        // 같은 구역, 번호만 다름 → 번호축
        if zones.count <= 1, numbers.count >= 2 {
            guard let fit = fitLine(usable, index: { $0.numberValue }) else {
                return makeResult(stage: .searching, target: nil, residual: 0, count: usable.count)
            }
            referencePitch = simd_length(fit.direction)
            // 1D는 2점=정확결정계 — 잔차는 3점부터 의미 (설계 개정 v2)
            let residualInformative = usable.count >= ParkingTuning.residualInformativeMinCount1D
            if residualInformative {
                updateDegradation(residual: fit.residualRMS, spacing: simd_length(fit.direction))
            }
            if isDegraded {
                return makeResult(stage: .degraded, target: nil, residual: fit.residualRMS, count: usable.count,
                                  residualInformative: residualInformative)
            }
            guard let n = targetNumber else {
                return makeResult(stage: .needMoreObservation(missing: .number), target: nil,
                                  residual: fit.residualRMS, count: usable.count,
                                  residualInformative: residualInformative)
            }
            if Self.stepAbsurd(fit.direction) {
                return makeResult(stage: .needMoreObservation(missing: .number), target: nil,
                                  residual: fit.residualRMS, count: usable.count,
                                  residualInformative: residualInformative)
            }
            // FR-109: 목표 구역이 관측 구역과 달라도 안내를 포기하지 않는다.
            // 미지 구역축 오프셋은 대칭 불확실성으로 표현되어 점추정을 이동시키지 않는다(FR-101).
            let zoneOffsetSteps = Self.offsetSteps(target: targetZoneIndex, observed: zones.first)
            let lever = fit.lever(at: Double(n))
            let fitUncertainty = max(ParkingTuning.fitUncertaintyFloor, fit.residualRMS * lever)
            observedNumberPitch = simd_length(fit.direction)
            return makeResult(stage: .axisGuidance(axis: .number), target: fit.predict(Double(n)),
                              residual: fit.residualRMS, count: usable.count,
                              origin: fit.base - fit.meanIndex * fit.direction, numVec: fit.direction,
                              residualInformative: residualInformative, lever: lever,
                              uncertainty: .init(
                                  // 미지 축 = 구역축. 세션 중 추정된 적 있으면 그 값 우선 (FR-101)
                                  unknownAxis: zoneOffsetSteps
                                      * (observedZonePitch ?? ParkingTuning.unknownZoneAxisPitchPrior),
                                  fit: fitUncertainty,
                                  expansion: expansion
                              ),
                              stepNormal: Self.stepNormal(fit.direction))
        }

        // 같은 번호, 구역만 다름 → 구역축
        if numbers.count <= 1, zones.count >= 2 {
            guard let fit = fitLine(usable, index: { $0.zoneIndex }) else {
                return makeResult(stage: .searching, target: nil, residual: 0, count: usable.count)
            }
            referencePitch = simd_length(fit.direction)
            let residualInformative = usable.count >= ParkingTuning.residualInformativeMinCount1D
            if residualInformative {
                updateDegradation(residual: fit.residualRMS, spacing: simd_length(fit.direction))
            }
            if isDegraded {
                return makeResult(stage: .degraded, target: nil, residual: fit.residualRMS, count: usable.count,
                                  residualInformative: residualInformative)
            }
            guard let zi = targetZoneIndex else {
                return makeResult(stage: .needMoreObservation(missing: .zone), target: nil,
                                  residual: fit.residualRMS, count: usable.count,
                                  residualInformative: residualInformative)
            }
            if Self.stepAbsurd(fit.direction) {
                return makeResult(stage: .needMoreObservation(missing: .zone), target: nil,
                                  residual: fit.residualRMS, count: usable.count,
                                  residualInformative: residualInformative)
            }
            // FR-109: 목표 번호가 관측 번호와 달라도 안내한다 (260919 J5 vs 관측 4행 사례)
            let numberOffsetSteps = Self.offsetSteps(target: targetNumber, observed: numbers.first)
            let lever = fit.lever(at: Double(zi))
            let fitUncertainty = max(ParkingTuning.fitUncertaintyFloor, fit.residualRMS * lever)
            observedZonePitch = simd_length(fit.direction)
            return makeResult(stage: .axisGuidance(axis: .zone), target: fit.predict(Double(zi)),
                              residual: fit.residualRMS, count: usable.count,
                              origin: fit.base - fit.meanIndex * fit.direction, zoneVec: fit.direction,
                              residualInformative: residualInformative, lever: lever,
                              uncertainty: .init(
                                  // 미지 축 = 번호축. 세션 중 추정된 적 있으면 그 값 우선 (FR-101)
                                  unknownAxis: numberOffsetSteps
                                      * (observedNumberPitch ?? ParkingTuning.unknownNumberAxisPitchPrior),
                                  fit: fitUncertainty,
                                  expansion: expansion
                              ),
                              stepNormal: Self.stepNormal(fit.direction))
        }

        // 구역·번호 모두 다름(혼합축) — 변위 분해 불가 (FR-009c)
        return makeResult(stage: .needMoreObservation(missing: .number), target: nil,
                          residual: 0, count: usable.count)
    }

    // MARK: - 모순 감지 (FR-012)

    private mutating func updateDegradation(residual: Double, spacing: Double) {
        let limit = max(ParkingTuning.residualLimitFloor, spacing * ParkingTuning.residualSpacingFactor)
        if residual > limit {
            if !isDegraded {
                isDegraded = true
            }
            consistentCount = 0
        } else if isDegraded {
            consistentCount += 1
            if consistentCount >= ParkingTuning.recoveryConsistentCount {
                isDegraded = false
                consistentCount = 0
            }
        }
    }

    private func makeResult(
        stage: GridEstimate.Stage,
        target: SIMD2<Double>?,
        residual: Double,
        count: Int,
        origin: SIMD2<Double>? = nil,
        zoneVec: SIMD2<Double>? = nil,
        numVec: SIMD2<Double>? = nil,
        residualInformative: Bool = false,
        lever: Double? = nil,
        uncertainty: GridEstimate.Uncertainty = .init(),
        stepNormal: Bool = true
    ) -> GridEstimate {
        let percent = confidencePercent(
            residual: residual, count: count, residualInformative: residualInformative,
            uncertainty: uncertainty, hasTarget: target != nil, stepNormal: stepNormal
        )
        return GridEstimate(
            stage: stage,
            targetPosition: target,
            residualRMS: residual,
            confidence: Self.level(forPercent: percent),
            observationCount: count,
            confidencePercent: percent,
            uncertainty: uncertainty,
            observationSpan: span,
            origin: origin,
            zoneVec: zoneVec,
            numVec: numVec,
            extrapolationLever: lever
        )
    }

    /// FR-103 연속 점수 → 백분율. 상한 95(100 미표시).
    /// 설계 의도: 관측 수가 바닥을 정하고, 불확실성 비율이 그것을 깎고, 잔차·인접이 보정한다.
    private func confidencePercent(
        residual: Double,
        count: Int,
        residualInformative: Bool,
        uncertainty: GridEstimate.Uncertainty,
        hasTarget: Bool,
        stepNormal: Bool
    ) -> Int {
        guard hasTarget else { return ParkingTuning.confidencePercentFloor }

        // ① 관측 수 바닥
        var score: Double
        switch count {
        case ..<ParkingTuning.observationsForSolid: score = 0.25
        case ParkingTuning.observationsForSolid: score = 0.45
        case ..<ParkingTuning.observationsForTop: score = 0.55
        default: score = 0.65
        }

        // ② 잔차 — 정확결정계에서는 항등 0이라 무정보(FR-104①). 가산하지 않고 상한만 낮춘다
        var cap = Double(ParkingTuning.confidencePercentCap) / 100.0
        if residualInformative {
            if residual < 1.0 { score += 0.15 }
            else if residual < 2.0 { score += 0.05 }
            else { score -= 0.10 }
        } else {
            cap = min(cap, 0.60)   // 잔차가 무정보면 중간 구간 위로 올라갈 수 없다
        }

        // ③ 인접 코드 목격 — 격자 품질과 독립인 "차 근처" 신호 (005 FR-013a)
        if neighborSighted { score += 0.10 }

        // ④ 불확실성 비율 — 스텝 피치 대비 U가 클수록 감쇠. U=피치면 절반
        let pitch = max(referencePitch, 1.0)
        score *= 1.0 / (1.0 + uncertainty.radius / pitch)

        // ⑤ 축 간격이 실측 정상 범위 밖이면 감점(차단은 FR-105 부조리 범위에서만)
        if !stepNormal { score *= 0.7 }

        // ⑥ FR-104 최상위 구간 AND 게이트 — 관측 수·잔차 정보·인접 목격을 모두 만족해야 70% 위로 간다.
        //    (PR#59 리뷰: 인접 목격이 가산일 뿐이라 5점·잔차만으로 80%에 도달하던 문제)
        let topTierAllowed = count >= ParkingTuning.observationsForTop && residualInformative && neighborSighted
        if !topTierAllowed {
            cap = min(cap, Double(ParkingTuning.confidencePercentTopThreshold - 1) / 100.0)
        }

        let clamped = min(cap, max(Double(ParkingTuning.confidencePercentFloor) / 100.0, score))
        return Int((clamped * 100).rounded())
    }

    /// 구 3단계 신뢰도 — 로그·도구 호환용 파생값 (FR-115)
    static func level(forPercent percent: Int) -> GridEstimate.Confidence {
        if percent >= ParkingTuning.confidencePercentTopThreshold { return .high }
        if percent >= ParkingTuning.confidencePercentSolidThreshold { return .medium }
        return .low
    }

    // MARK: - v3 헬퍼 (FR-101/105/108)

    /// FR-105 위생 검사 — 명백한 부조리(안전망 아님)
    private static func stepAbsurd(_ step: SIMD2<Double>) -> Bool {
        let magnitude = simd_length(step)
        return magnitude < ParkingTuning.axisStepAbsurdMin || magnitude > ParkingTuning.axisStepAbsurdMax
    }

    /// 실측 정상 범위 — 벗어나면 백분율 감점
    private static func stepNormal(_ step: SIMD2<Double>) -> Bool {
        let magnitude = simd_length(step)
        return magnitude >= ParkingTuning.axisStepNormalMin && magnitude <= ParkingTuning.axisStepNormalMax
    }

    /// 목표가 관측 축 밖으로 벗어난 스텝 수 (미지 축 오프셋)
    private static func offsetSteps(target: Int?, observed: Int?) -> Double {
        guard let target, let observed else { return 0 }
        return Double(abs(target - observed))
    }

    /// FR-108 팽창 — 채택 관측의 **평균** 노화 기준.
    /// 최댓값을 쓰면 오래된 관측 하나가 딕셔너리에 남는 한 새 기둥을 아무리 비춰도 상한까지 래칫되어
    /// "새 관측이 들어오면 회복된다"가 성립하지 않는다(PR#59 리뷰). 평균은 새 관측이 들어올수록 내려간다.
    private static func expansion(of observations: [GridObservation]) -> Double {
        guard !observations.isEmpty else { return 0 }
        let mean = observations.map(\.ageSeconds).reduce(0, +) / Double(observations.count)
        guard mean > 0 else { return 0 }
        return min(ParkingTuning.expansionMaxMeters, mean * ParkingTuning.expansionMetersPerSecond)
    }


    /// FR-106 기준량 — 랜드마크 간 최대 이격
    private static func span(of observations: [GridObservation]) -> Double {
        guard observations.count >= 2 else { return 0 }
        var maximum = 0.0
        for i in 0..<observations.count {
            for j in (i + 1)..<observations.count {
                maximum = max(maximum, simd_distance(observations[i].position, observations[j].position))
            }
        }
        return maximum
    }

    /// G1: 아핀 외삽 레버 √(aᵀM⁻¹a), a = [1, 목표구역, 목표번호]
    private static func affineLever(_ normalMatrix: [[Double]], targetZone: Int, targetNumber: Int) -> Double? {
        let a = [1.0, Double(targetZone), Double(targetNumber)]
        guard let x = solve3x3(normalMatrix, a) else { return nil }
        let value = zip(a, x).map(*).reduce(0, +)
        return value >= 0 ? value.squareRoot() : nil
    }

    // MARK: - 아핀 피팅 (3+ 비공선)

    /// p ≈ origin + zoneIndex·zoneVec + number·numVec — x/y 성분이 분리되므로 3x3 정규방정식 2회
    private struct AffineFit {
        let origin: SIMD2<Double>
        let zoneVec: SIMD2<Double>
        let numVec: SIMD2<Double>

        func predict(zoneIndex: Int, number: Int) -> SIMD2<Double> {
            origin + Double(zoneIndex) * zoneVec + Double(number) * numVec
        }

        func residualRMS(over observations: [GridObservation]) -> Double {
            let residuals = observations.compactMap { obs -> Double? in
                guard let z = obs.zoneIndex, let n = obs.numberValue else { return nil }
                let predicted = predict(zoneIndex: z, number: n)
                return simd_length_squared(predicted - obs.position)
            }
            guard !residuals.isEmpty else { return 0 }
            return (residuals.reduce(0, +) / Double(residuals.count)).squareRoot()
        }

        /// 기둥 간격 추정 — 잔차 임계의 스케일 기준
        var spacingEstimate: Double {
            max(simd_length(zoneVec), simd_length(numVec))
        }
    }

    /// 반환에 정규방정식 행렬 M 포함 — G1 외삽 레버 계산용 (설계 개정 v2)
    private func fitAffine(_ observations: [GridObservation]) -> (AffineFit, [[Double]])? {
        let points = observations.compactMap { obs -> (z: Double, n: Double, p: SIMD2<Double>)? in
            guard let z = obs.zoneIndex, let n = obs.numberValue else { return nil }
            return (Double(z), Double(n), obs.position)
        }
        guard points.count >= 3 else { return nil }

        // 정규방정식 M·c = b, M = Σ [1,z,n]ᵀ[1,z,n]
        var m = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var bx = [Double](repeating: 0, count: 3)
        var by = [Double](repeating: 0, count: 3)
        for (z, n, p) in points {
            let row = [1.0, z, n]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += row[i] * row[j] }
                bx[i] += row[i] * p.x
                by[i] += row[i] * p.y
            }
        }
        guard let cx = Self.solve3x3(m, bx), let cy = Self.solve3x3(m, by) else {
            return nil   // 인덱스 공선(구역·번호 변화가 상관) → 1D로 하강
        }
        let fit = AffineFit(
            origin: SIMD2(cx[0], cy[0]),
            zoneVec: SIMD2(cx[1], cy[1]),
            numVec: SIMD2(cx[2], cy[2])
        )
        return (fit, m)
    }

    private static func solve3x3(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        for pivot in 0..<3 {
            var maxRow = pivot
            for row in (pivot + 1)..<3 where abs(a[row][pivot]) > abs(a[maxRow][pivot]) {
                maxRow = row
            }
            if abs(a[maxRow][pivot]) < 1e-9 { return nil }
            a.swapAt(pivot, maxRow)
            b.swapAt(pivot, maxRow)
            for row in (pivot + 1)..<3 {
                let factor = a[row][pivot] / a[pivot][pivot]
                for col in pivot..<3 { a[row][col] -= factor * a[pivot][col] }
                b[row] -= factor * b[pivot]
            }
        }
        var x = [Double](repeating: 0, count: 3)
        for row in stride(from: 2, through: 0, by: -1) {
            var sum = b[row]
            for col in (row + 1)..<3 { sum -= a[row][col] * x[col] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    // MARK: - 1D 최소제곱

    private struct LineFit {
        let base: SIMD2<Double>       // 인덱스 평균 위치
        let meanIndex: Double
        let direction: SIMD2<Double>  // 인덱스 1스텝당 변위
        let residualRMS: Double
        let pointCount: Int
        let indexSpread: Double       // Σ(i - meanIndex)² — 레버 계산용

        func predict(_ index: Double) -> SIMD2<Double> {
            base + (index - meanIndex) * direction
        }

        /// G1: 1D 외삽 레버 √(1/n + (t−ī)²/Σ(i−ī)²) (설계 개정 v2)
        func lever(at index: Double) -> Double {
            guard indexSpread > 1e-9 else { return .infinity }
            let value = 1.0 / Double(pointCount) + (index - meanIndex) * (index - meanIndex) / indexSpread
            return value.squareRoot()
        }
    }

    private func fitLine(
        _ observations: [GridObservation],
        index: (GridObservation) -> Int?
    ) -> LineFit? {
        let points = observations.compactMap { obs -> (i: Double, p: SIMD2<Double>)? in
            guard let idx = index(obs) else { return nil }
            return (Double(idx), obs.position)
        }
        guard points.count >= 2 else { return nil }

        let meanIndex = points.map(\.i).reduce(0, +) / Double(points.count)
        let meanPos = points.map(\.p).reduce(SIMD2<Double>.zero, +) / Double(points.count)
        var numerator = SIMD2<Double>.zero
        var denominator = 0.0
        for (i, p) in points {
            numerator += (i - meanIndex) * (p - meanPos)
            denominator += (i - meanIndex) * (i - meanIndex)
        }
        guard denominator > 1e-9 else { return nil }
        let direction = numerator / denominator

        let residuals = points.map { point -> Double in
            let predicted = meanPos + (point.i - meanIndex) * direction
            return simd_length_squared(predicted - point.p)
        }
        let rms = (residuals.reduce(0, +) / Double(residuals.count)).squareRoot()

        return LineFit(base: meanPos, meanIndex: meanIndex, direction: direction, residualRMS: rms,
                       pointCount: points.count, indexSpread: denominator)
    }
}
