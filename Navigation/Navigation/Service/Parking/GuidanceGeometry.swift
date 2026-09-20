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

    /// 보장이 성립하지 않는 이유 — 사용자 문구가 원인을 단정하지 않도록 구분한다(PR#59 리뷰).
    /// 45m·68m 떨어진 상태에서 "거의 다 왔다"고 말하던 문제의 원인.
    enum GuaranteeFailure: Equatable, Sendable {
        /// 목표에 충분히 가까워져 방위가 어느 쪽으로든 열림 — 진짜 근접
        case proximity
        /// 관측 배치 규모 대비 너무 먼 외삽 — 아직 근거가 부족 (J21·260919 사고 구조)
        case beyondObservationSpan
        /// 불확실성이 커서 방위 상한을 못 지킴
        case uncertaintyTooLarge
    }

    struct Evaluation: Equatable, Sendable {
        /// 기기 전방 기준 시계방향(+) 화살표 각(rad)
        let arrowRadians: Double
        /// 추정 거리 d̂(m)
        let distance: Double
        /// 측방 보장 각 asin(U/d̂)(rad) — 보장 불가 시 π/2
        let guaranteeAngle: Double
        /// FR-101 — 화살표를 표시해도 되는가
        let isDirectionGuaranteed: Bool
        /// FR-106 + FR-103 — 거리를 숫자로 보여도 되는가
        let isDistanceDisplayable: Bool
        /// 보장 실패 원인 (성립 시 nil)
        let failure: GuaranteeFailure?
        /// FR-103 표시 백분율 — 추정 품질에 현재 시점의 기하 위험(보장 각 여유)을 반영한 값
        let displayPercent: Int
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

        // 측방 상한은 접선 관계 asin(U/d̂) — 분모에 d̂−U를 쓰면 실효 임계가 30°가 아니라 19.5°가 되어
        // 캘리브레이션 대상(SC-102)과 어긋난다 (PR#59 리뷰)
        let guaranteeAngle = distance > radius ? asin(min(1, radius / distance)) : .pi / 2
        let angleOK = distance > radius && guaranteeAngle <= ParkingTuning.guaranteeMaxAngle

        // FR-106: 기준량은 랜드마크 간 이격 — 기기 이동 경로는 포함하지 않는다.
        // PR#59 리뷰 반영: 거리 숫자뿐 아니라 화살표 표시 자체에 적용한다.
        // 실측상 이 비율이 사고(3.0~4.8배)와 도착 성공(1배 미만)을 가르는 유일한 지표였다.
        let spanLimit = observationSpan * ParkingTuning.displayDistanceSpanFactor
        let withinSpan = spanLimit > 0 && distance <= spanLimit

        let guaranteed = angleOK && withinSpan
        let failure: GuaranteeFailure?
        if guaranteed {
            failure = nil
        } else if !withinSpan {
            failure = .beyondObservationSpan
        } else if distance <= radius {
            failure = .proximity
        } else {
            failure = .uncertaintyTooLarge
        }

        let direction = distance > 1e-6 ? toTarget / distance : deviceForward
        // 부호 규약: 전방 기준 시계방향(+) — 화면 회전값으로 직접 사용 (005에서 현장 검증됨)
        let arrow = atan2(
            deviceForward.x * direction.y - deviceForward.y * direction.x,
            simd_dot(deviceForward, direction)
        )

        // FR-103: 백분율은 추정 품질만이 아니라 "지금 이 시점의 기하 위험"을 담아야 한다.
        // 리뷰 반례: 방위오차 0.6°가 29%(점선)인데 14.2°가 49%(실선+거리)로 역전됐다 —
        // 보장 각이 임계에 가까울수록 깎아 순서를 바로잡는다.
        let angleRatio = min(1, guaranteeAngle / ParkingTuning.guaranteeMaxAngle)
        let adjusted = Double(confidencePercent) * (1.0 - 0.5 * angleRatio)
        let displayPercent = max(ParkingTuning.confidencePercentFloor, Int(adjusted.rounded()))

        let distanceDisplayable = guaranteed
            && displayPercent >= ParkingTuning.confidencePercentSolidThreshold

        return Evaluation(
            arrowRadians: arrow,
            distance: distance,
            guaranteeAngle: guaranteeAngle,
            isDirectionGuaranteed: guaranteed,
            isDistanceDisplayable: distanceDisplayable,
            failure: failure,
            displayPercent: displayPercent
        )
    }
}
