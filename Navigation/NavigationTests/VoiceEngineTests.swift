import Testing
import CoreLocation
@testable import Navigation

struct VoiceEngineTests {

    // MARK: - Helpers

    private func makeStep(
        instructions: String = "우회전",
        distance: CLLocationDistance = 500,
        turnType: TurnType = .rightTurn,
        roadName: String? = "테헤란로"
    ) -> RouteStep {
        RouteStep(
            instructions: instructions,
            distance: distance,
            polylineCoordinates: [],
            duration: 60,
            turnType: turnType,
            roadName: roadName
        )
    }

    // MARK: - 초기 안내

    @Test func initialAnnouncement_firesOnce() {
        let engine = VoiceEngine(provider: .kakao)

        let first = engine.checkInitial()
        #expect(first != nil)
        #expect(first?.text == "경로 안내를 시작합니다")

        let second = engine.checkInitial()
        #expect(second == nil)  // 두 번째는 nil
    }

    // MARK: - 1200m 트리거 (일반도로)

    @Test func trigger_preRoadName_kakao() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep(roadName: "테헤란로")

        let cmd = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)

        #expect(cmd != nil)
        #expect(cmd?.text.contains("테헤란로") == true)
        #expect(cmd?.text.contains("우회전") == true)
    }

    // MARK: - 300m 트리거 (일반도로)

    @Test func trigger_preDistance_normal() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep()

        // 1200m 먼저 소비
        _ = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)

        let cmd = engine.check(distanceToManeuver: 300, speed: 15, stepIndex: 0, step: step)

        #expect(cmd != nil)
        #expect(cmd?.text.contains("300미터") == true || cmd?.text.contains("미터") == true)
    }

    // MARK: - 120m 트리거 (일반도로)

    @Test func trigger_imminent_normal() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep()

        _ = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)
        _ = engine.check(distanceToManeuver: 300, speed: 15, stepIndex: 0, step: step)

        let cmd = engine.check(distanceToManeuver: 120, speed: 15, stepIndex: 0, step: step)

        #expect(cmd != nil)
        #expect(cmd?.text.contains("전방") == true)
    }

    // MARK: - 500m 트리거 (고속도로)

    @Test func trigger_preDistance_highway() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep()

        _ = engine.check(distanceToManeuver: 1200, speed: 25, stepIndex: 0, step: step)  // 90km/h

        let cmd = engine.check(distanceToManeuver: 500, speed: 25, stepIndex: 0, step: step)

        #expect(cmd != nil)
        #expect(cmd?.text.contains("500미터") == true || cmd?.text.contains("미터") == true)
    }

    // MARK: - 중복 방지

    @Test func duplicatePrevention_sameBand() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep()

        let first = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)
        #expect(first != nil)

        let second = engine.check(distanceToManeuver: 1180, speed: 15, stepIndex: 0, step: step)
        #expect(second == nil)  // 같은 밴드 재트리거 안 됨
    }

    // MARK: - 짧은 스텝 (100m) → 즉시 안내

    @Test func shortStep_triggersImmediately() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep(distance: 100)

        // 100m 스텝 → 1200m/300m 밴드 스킵, imminent로 즉시 안내
        let cmd = engine.check(distanceToManeuver: 100, speed: 15, stepIndex: 0, step: step)

        #expect(cmd != nil)
    }

    // MARK: - Apple 텍스트

    @Test func appleProvider_usesInstructions() {
        let engine = VoiceEngine(provider: .apple)
        let step = makeStep(instructions: "상암사거리에서 증산로(으)로 좌회전")

        let cmd = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)

        #expect(cmd != nil)
        #expect(cmd?.text == "상암사거리에서 증산로(으)로 좌회전")
    }

    @Test func appleProvider_preDistance_addsPrefix() {
        let engine = VoiceEngine(provider: .apple)
        let step = makeStep(instructions: "좌회전")

        _ = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)

        let cmd = engine.check(distanceToManeuver: 300, speed: 15, stepIndex: 0, step: step)

        #expect(cmd != nil)
        #expect(cmd?.text.contains("앞") == true)
        #expect(cmd?.text.contains("좌회전") == true)
    }

    // MARK: - 스텝 전진 시 이전 기록 정리

    @Test func onStepAdvanced_clearsOldKeys() {
        let engine = VoiceEngine(provider: .kakao)
        let step0 = makeStep()
        let step1 = makeStep(instructions: "좌회전", turnType: .leftTurn, roadName: "강남대로")

        // Step 0에서 1200m 안내
        _ = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step0)

        // Step 전진
        engine.onStepAdvanced(previousStepIndex: 0)

        // Step 1에서 1200m 안내 — 새 스텝이므로 가능
        let cmd = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 1, step: step1)
        #expect(cmd != nil)
        #expect(cmd?.text.contains("강남대로") == true)
    }

    // MARK: - 리셋

    @Test func reset_clearsAll() {
        let engine = VoiceEngine(provider: .kakao)
        let step = makeStep()

        _ = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)
        _ = engine.checkInitial()

        engine.reset()

        // 리셋 후 다시 안내 가능
        let initial = engine.checkInitial()
        #expect(initial != nil)

        let cmd = engine.check(distanceToManeuver: 1200, speed: 15, stepIndex: 0, step: step)
        #expect(cmd != nil)
    }
}
