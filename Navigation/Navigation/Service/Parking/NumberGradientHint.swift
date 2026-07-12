import Foundation

/// 근접확인(강등) 모드의 번호 그라디언트 힌트 (FR-012).
/// 번호는 통로 경로를 따라 단조 증가하므로, 접힌(스네이크) 배치에서 방향 벡터가 무효해도
/// "목표 번호와의 차이·추이"는 유효한 warmer/colder 신호다 (260710 현장 로그 주차장 = 번호 단독 체계).
/// 순수 계산 — 리플레이·유닛 테스트 대상.
struct NumberGradientHint: Sendable {

    /// "거의 다 왔어요"로 전환하는 번호 차이 상한
    static let nearThreshold = 3

    private var lastMagnitude: Int?

    /// 새 확정 관측 번호에 대한 힌트 문구.
    /// 호출 측 계약: 목표와 같은 구역(또는 둘 다 구역 없음)의 관측만 전달할 것 — 구역별 번호 리셋 방어.
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
