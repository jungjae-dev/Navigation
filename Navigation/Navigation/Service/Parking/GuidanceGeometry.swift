import Foundation
import simd

/// 화살표 표시 가능 여부 판정 — FR-101 측방 각도 보장, FR-106 거리 표시 규칙.
/// 순수 함수(기기 포즈 + 목표 추정 + 불확실성)라 리플레이로 재현된다(005 DR-003 계약).
///
/// 설계 근거(PR#58 리뷰): 표시 기준을 "미지 축이 있느냐"로 두면 두 축이 모두 성립한 순간
/// 판정이 공회전한다 — 과거 과신 사고(J21 102m·J22 30.3m)가 전부 그 상태였다.
/// 그래서 기준을 측방 불확실성 전체(미지 축 + 적합 + 팽창)로 잡고,
/// 거리는 추정값이 아니라 하한 d⁻를 쓴다(추정이 멀수록 통과하기 쉬워지는 역단조성 차단).
nonisolated enum GuidanceGeometry {

    struct Evaluation: Equatable, Sendable {
        /// 기기 전방 기준 시계방향(+) 화살표 각(rad)
        let arrowRadians: Double
        /// 추정 거리 d̂(m)
        let distance: Double
        /// 보수적 거리 하한 d⁻(m)
        let distanceLowerBound: Double
        /// 측방 보장 각 asin(U/d⁻)(rad) — 보장 불가 시 π/2
        let guaranteeAngle: Double
        /// FR-101 — 화살표를 표시해도 되는가
        let isDirectionGuaranteed: Bool
        /// FR-106 + FR-103 — 거리를 숫자로 보여도 되는가
        let isDistanceDisplayable: Bool
    }

    static func evaluate(
        target: SIMD2<Double>,
        uncertainty: GridEstimate.Uncertainty,
        devicePosition: SIMD2<Double>,
        deviceForward: SIMD2<Double>,
        observationSpan: Double,
        confidencePercent: Int
    ) -> Evaluation {
        let toTarget = target - devicePosition
        let distance = simd_length(toTarget)
        let radius = max(0, uncertainty.radius)
        let lowerBound = max(0, distance - radius)

        let guaranteeAngle: Double
        let guaranteed: Bool
        if lowerBound > radius {
            guaranteeAngle = asin(min(1, radius / lowerBound))
            guaranteed = guaranteeAngle <= ParkingTuning.guaranteeMaxAngle
        } else {
            // 불확실성이 거리에 필적 — 방위가 어느 쪽으로든 열린다(근접 모드 전환점, FR-102)
            guaranteeAngle = .pi / 2
            guaranteed = false
        }

        let direction = distance > 1e-6 ? toTarget / distance : deviceForward
        // 부호 규약: 전방 기준 시계방향(+) — 화면 회전값으로 직접 사용 (005에서 현장 검증됨)
        let arrow = atan2(
            deviceForward.x * direction.y - deviceForward.y * direction.x,
            simd_dot(deviceForward, direction)
        )

        // FR-106: 기준량은 랜드마크 간 이격 — 기기 이동 경로는 포함하지 않는다
        let spanLimit = observationSpan * ParkingTuning.displayDistanceSpanFactor
        let withinSpan = spanLimit <= 0 ? false : distance <= spanLimit
        let distanceDisplayable = guaranteed
            && confidencePercent >= ParkingTuning.confidencePercentSolidThreshold
            && withinSpan

        return Evaluation(
            arrowRadians: arrow,
            distance: distance,
            distanceLowerBound: lowerBound,
            guaranteeAngle: guaranteeAngle,
            isDirectionGuaranteed: guaranteed,
            isDistanceDisplayable: distanceDisplayable
        )
    }
}
