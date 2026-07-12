import Testing
@testable import Navigation

/// 번호 그라디언트 힌트 — 강등 모드의 warmer/colder (FR-012, 260712 백로그 4)
struct NumberGradientHintTests {

    @Test func firstObservationGivesDirection() {
        var hint = NumberGradientHint()
        // 목표 9, 지금 27 → 번호가 작아지는 쪽
        let message = hint.hint(targetNumber: 9, observedNumber: 27)
        #expect(message.contains("작아지는"))
        #expect(message.contains("27"))
        #expect(message.contains("9"))
    }

    @Test func oppositeDirectionWhenTargetIsLarger() {
        var hint = NumberGradientHint()
        // 목표 60, 지금 12 → 커지는 쪽
        let message = hint.hint(targetNumber: 60, observedNumber: 12)
        #expect(message.contains("커지는"))
    }

    @Test func gettingCloserIsWarmer() {
        var hint = NumberGradientHint()
        _ = hint.hint(targetNumber: 9, observedNumber: 27)   // |차이| 18
        let message = hint.hint(targetNumber: 9, observedNumber: 18)   // |차이| 9 — 감소
        #expect(message.contains("가까워지고"))
    }

    @Test func gettingFartherIsColder() {
        var hint = NumberGradientHint()
        _ = hint.hint(targetNumber: 9, observedNumber: 27)   // 18
        let message = hint.hint(targetNumber: 9, observedNumber: 33)   // 24 — 증가
        #expect(message.contains("반대"))
        #expect(message.contains("작아지는"))   // 교정 방향도 함께
    }

    @Test func nearTargetSwitchesToDirectConfirm() {
        var hint = NumberGradientHint()
        let message = hint.hint(targetNumber: 9, observedNumber: 11)   // |차이| 2 ≤ 3
        #expect(message.contains("거의 다 왔어요"))
        #expect(message.contains("9"))
    }

    @Test func sameMagnitudeRepeatsDirectionWithoutJudgement() {
        var hint = NumberGradientHint()
        _ = hint.hint(targetNumber: 9, observedNumber: 27)
        let message = hint.hint(targetNumber: 9, observedNumber: 27)   // 같은 차이 — 판정 없음
        #expect(!message.contains("가까워지고"))
        #expect(!message.contains("반대"))
        #expect(message.contains("작아지는"))
    }

    @Test func resetClearsTrend() {
        var hint = NumberGradientHint()
        _ = hint.hint(targetNumber: 9, observedNumber: 27)
        hint.reset()
        // 리셋 후 첫 관측은 추이 판정 없이 방향만
        let message = hint.hint(targetNumber: 9, observedNumber: 18)
        #expect(!message.contains("가까워지고"))
        #expect(message.contains("작아지는"))
    }
}
