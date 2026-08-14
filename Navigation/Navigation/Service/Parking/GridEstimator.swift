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

    let stage: Stage
    /// 목표 외삽 위치 (xz) — axisGuidance/gridGuidance에서만 non-nil
    let targetPosition: SIMD2<Double>?
    let residualRMS: Double
    let confidence: Confidence
    let observationCount: Int
    /// 디버그 시각화용 피팅 모델 (DR-001) — 관측 인덱스의 예측 위치 재계산에 사용
    var origin: SIMD2<Double>? = nil
    var zoneVec: SIMD2<Double>? = nil
    var numVec: SIMD2<Double>? = nil

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

    // MARK: - Update

    mutating func markNeighborSighted() {
        neighborSighted = true
    }

    /// 관측 전체 무효화 후 재시작 (백그라운드 복귀)
    mutating func reset() {
        isDegraded = false
        consistentCount = 0
        neighborSighted = false
    }

    /// 누적 관측 전체로 재추정 (매 관측 갱신마다 호출 — FR-011)
    mutating func estimate(
        observations: [GridObservation],
        targetZoneIndex: Int?,
        targetNumber: Int?
    ) -> GridEstimate {
        // 신선도 필터: 오래 재관측 안 된 좌표는 드리프트 오염 가능 → 제외 (260801 로그 반영)
        let usable = observations.filter { $0.ageSeconds <= ParkingTuning.observationStaleAfter }

        guard usable.count >= 2 else {
            return makeResult(stage: .searching, target: nil, residual: 0, count: usable.count)
        }

        // 2D 아핀 시도 (비공선 3개 이상) → 실패 시 1D 축으로 단계 하강
        if usable.count >= 3,
           let affine = fitAffine(usable) {
            let residual = affine.residualRMS(over: usable)
            updateDegradation(residual: residual, spacing: affine.spacingEstimate)

            if isDegraded {
                return makeResult(stage: .degraded, target: nil, residual: residual, count: usable.count)
            }
            guard let zi = targetZoneIndex, let n = targetNumber else {
                // 목표 인덱스 불완전(파싱 불가 세션은 상류에서 차단) — 방어적 강등
                return makeResult(stage: .degraded, target: nil, residual: residual, count: usable.count)
            }
            let target = affine.predict(zoneIndex: zi, number: n)
            return makeResult(stage: .gridGuidance, target: target, residual: residual, count: usable.count,
                              origin: affine.origin, zoneVec: affine.zoneVec, numVec: affine.numVec)
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
            updateDegradation(residual: fit.residualRMS, spacing: simd_length(fit.direction))
            if isDegraded {
                return makeResult(stage: .degraded, target: nil, residual: fit.residualRMS, count: usable.count)
            }
            // 목표가 이 축 위인가 — 구역이 다르면 구역축 미지 (FR-009b)
            let observedZone = zones.first
            if let targetZone = targetZoneIndex, let obsZone = observedZone, targetZone != obsZone {
                return makeResult(stage: .needMoreObservation(missing: .zone), target: nil,
                                  residual: fit.residualRMS, count: usable.count)
            }
            guard let n = targetNumber else {
                return makeResult(stage: .needMoreObservation(missing: .number), target: nil,
                                  residual: fit.residualRMS, count: usable.count)
            }
            return makeResult(stage: .axisGuidance(axis: .number), target: fit.predict(Double(n)),
                              residual: fit.residualRMS, count: usable.count,
                              origin: fit.base - fit.meanIndex * fit.direction, numVec: fit.direction)
        }

        // 같은 번호, 구역만 다름 → 구역축
        if numbers.count <= 1, zones.count >= 2 {
            guard let fit = fitLine(usable, index: { $0.zoneIndex }) else {
                return makeResult(stage: .searching, target: nil, residual: 0, count: usable.count)
            }
            updateDegradation(residual: fit.residualRMS, spacing: simd_length(fit.direction))
            if isDegraded {
                return makeResult(stage: .degraded, target: nil, residual: fit.residualRMS, count: usable.count)
            }
            let observedNumber = numbers.first
            if let targetNum = targetNumber, let obsNum = observedNumber, targetNum != obsNum {
                return makeResult(stage: .needMoreObservation(missing: .number), target: nil,
                                  residual: fit.residualRMS, count: usable.count)
            }
            guard let zi = targetZoneIndex else {
                return makeResult(stage: .needMoreObservation(missing: .zone), target: nil,
                                  residual: fit.residualRMS, count: usable.count)
            }
            return makeResult(stage: .axisGuidance(axis: .zone), target: fit.predict(Double(zi)),
                              residual: fit.residualRMS, count: usable.count,
                              origin: fit.base - fit.meanIndex * fit.direction, zoneVec: fit.direction)
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
        numVec: SIMD2<Double>? = nil
    ) -> GridEstimate {
        GridEstimate(
            stage: stage,
            targetPosition: target,
            residualRMS: residual,
            confidence: confidence(residual: residual, count: count),
            observationCount: count,
            origin: origin,
            zoneVec: zoneVec,
            numVec: numVec
        )
    }

    private func confidence(residual: Double, count: Int) -> GridEstimate.Confidence {
        var level: GridEstimate.Confidence
        if count >= ParkingTuning.minObservationsForHighConfidence && residual < 1.0 {
            level = .high
        } else if count >= 3 || residual < 2.0 {
            level = .medium
        } else {
            level = .low
        }
        // 과신 방지 상한은 피팅 품질(기본 레벨)에만 적용 — 관측 수가 적으면 잔차가 낮아도 high 금지 (FR-010, 260801 반영).
        // 인접 목격 부스트(FR-013a)는 격자 품질과 독립적인 "차 근처" 신호라 상한 이후에 더한다.
        if count < ParkingTuning.minObservationsForHighConfidence, level == .high {
            level = .medium
        }
        if neighborSighted, level < .high {
            level = GridEstimate.Confidence(rawValue: level.rawValue + 1) ?? .high
        }
        return level
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

    private func fitAffine(_ observations: [GridObservation]) -> AffineFit? {
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
        return AffineFit(
            origin: SIMD2(cx[0], cy[0]),
            zoneVec: SIMD2(cx[1], cy[1]),
            numVec: SIMD2(cx[2], cy[2])
        )
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

        func predict(_ index: Double) -> SIMD2<Double> {
            base + (index - meanIndex) * direction
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

        return LineFit(base: meanPos, meanIndex: meanIndex, direction: direction, residualRMS: rms)
    }
}
