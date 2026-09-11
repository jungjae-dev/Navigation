import Foundation

/// 근접확인(강등) 모드의 번호 그라디언트 힌트 (FR-012).
/// 번호는 통로 경로를 따라 단조 증가하므로, 접힌(스네이크) 배치에서 방향 벡터가 무효해도
/// "목표 번호와의 차이·추이"는 유효한 warmer/colder 신호다 (260710 현장 로그 주차장 = 번호 단독 체계).
/// 순수 계산 — 리플레이·유닛 테스트 대상.
struct NumberGradientHint: Sendable {

    /// "거의 다 왔어요"로 전환하는 번호 차이 상한
    static let nearThreshold = 3

    private var lastMagnitude: Int?

    /// 확정 관측 1건에 대한 힌트 (구역·번호 종합).
    /// 위치(좌표)와 무관 — 다중 표지판으로 격자가 못 서는 주차장에서도 유효한 안내 (260911).
    /// - 다른 구역: 구역 서수 그라디언트 (추이 판정 없음 — 구역별 번호 리셋 방어)
    /// - 같은 구역(또는 둘 다 구역 없음): 번호 그라디언트 (추이 포함)
    mutating func hint(target: ParsedCode, observed: ParsedCode) -> String? {
        if let targetZone = target.zoneIndex, let observedZone = observed.zoneIndex,
           targetZone != observedZone,
           let targetToken = target.zoneToken, let observedToken = observed.zoneToken {
            lastMagnitude = nil   // 구역이 바뀌면 번호 추이는 무의미
            // 방향 어휘("앞/뒤") 금지 — 구역 글자 순서와 보행 경로의 정렬은 미검증 가정이고(260911 검증:
            // 한 세션에서 55° 어긋남), 주차장이 F·I 등을 건너뛰면 서수 자체가 어긋난다. 크기·근접만 말한다 (설계 개정 v2)
            if abs(targetZone - observedZone) == 1 {
                return "옆 구역이에요 — 근처 기둥에서 \(targetToken)구역을 찾아보세요"
            }
            return "지금 \(observedToken)구역 — 목표는 \(targetToken)구역이에요 (약 \(abs(targetZone - observedZone))개 구역 차이)"
        }
        guard target.zoneToken == observed.zoneToken,
              let targetNumber = target.numberValue, let observedNumber = observed.numberValue else {
            return nil
        }
        return hint(targetNumber: targetNumber, observedNumber: observedNumber)
    }

    /// 같은 구역(또는 구역 없음)의 번호 그라디언트 — warmer/colder 추이 포함.
    mutating func hint(targetNumber: Int, observedNumber: Int) -> String {
        let diff = targetNumber - observedNumber
        let magnitude = abs(diff)
        defer { lastMagnitude = magnitude }

        if magnitude <= Self.nearThreshold {
            return "거의 다 왔어요 — 주변에서 \(targetNumber)번을 확인하세요"
        }

        let direction = diff < 0 ? "작아지는" : "커지는"
        let position = "(지금 \(observedNumber) → 목표 \(targetNumber))"

        if let last = lastMagnitude {
            if magnitude < last {
                return "가까워지고 있어요 \(position)"
            }
            if magnitude > last {
                return "반대 방향이에요 — 번호가 \(direction) 쪽으로 \(position)"
            }
        }
        return "번호가 \(direction) 쪽으로 \(position)"
    }

    mutating func reset() {
        lastMagnitude = nil
    }
}
