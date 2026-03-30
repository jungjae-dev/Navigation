import Testing
import CoreLocation
@testable import Navigation

struct RouteTrackerTests {

    // MARK: - Test Route

    /// P0(37.5, 127.0) → G0(37.5, 127.005) → G1(37.5, 127.01) → G2(37.5, 127.015)
    /// 3스텝, 각 ~500m, 동쪽 방향
    static func makeTestRoute(provider: RouteProvider = .kakao) -> Route {
        let p0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0)
        let g0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005)
        let g1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.01)
        let g2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.015)

        return Route(
            id: "test",
            distance: 1500,
            expectedTravelTime: 300,  // 5분
            name: "테스트",
            steps: [
                RouteStep(
                    instructions: "직진",
                    distance: 500,
                    polylineCoordinates: [p0, g0],
                    duration: 100,
                    turnType: .straight,
                    roadName: "테헤란로"
                ),
                RouteStep(
                    instructions: "우회전",
                    distance: 500,
                    polylineCoordinates: [g0, g1],
                    duration: 100,
                    turnType: .rightTurn,
                    roadName: "강남대로"
                ),
                RouteStep(
                    instructions: "목적지",
                    distance: 500,
                    polylineCoordinates: [g1, g2],
                    duration: 100,
                    turnType: .destination,
                    roadName: nil
                ),
            ],
            polylineCoordinates: [p0, g0, g1, g2],
            transportMode: .automobile,
            provider: provider
        )
    }

    // MARK: - 초기 상태

    @Test func initialState_isStep0() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress = tracker.update(matchedPosition: pos)

        #expect(progress.currentStepIndex == 0)
        #expect(progress.currentStep.instructions == "직진")
        #expect(progress.nextStep?.instructions == "우회전")
        #expect(progress.totalSteps == 3)
    }

    // MARK: - 스텝 전진 (30m 이내)

    @Test func advancesStep_when30mOrLess() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // G0 (37.5, 127.005) 에서 25m 이내 = 약 (37.5, 127.00478)
        // G0 근처로 이동
        let nearG0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.00498)
        let progress = tracker.update(matchedPosition: nearG0)

        #expect(progress.currentStepIndex == 1)
        #expect(progress.currentStep.instructions == "우회전")
        #expect(progress.nextStep?.instructions == "목적지")
    }

    // MARK: - 스텝 유지 (31m 이상)

    @Test func keepsStep_whenMoreThan30m() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // G0에서 충분히 떨어진 위치
        let farFromG0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.004)
        let progress = tracker.update(matchedPosition: farFromG0)

        #expect(progress.currentStepIndex == 0)
        #expect(progress.currentStep.instructions == "직진")
    }

    // MARK: - 마지막 스텝에서 전진 안 함

    @Test func doesNotAdvancePastLastStep() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // Step 0 → 1 전진
        let nearG0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.00498)
        _ = tracker.update(matchedPosition: nearG0)

        // Step 1 → 2 전진
        let nearG1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.00998)
        _ = tracker.update(matchedPosition: nearG1)

        #expect(tracker.currentStepIndex == 2)

        // 마지막 스텝에서 더 전진하지 않음
        let nearG2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.01498)
        let progress = tracker.update(matchedPosition: nearG2)

        #expect(progress.currentStepIndex == 2)  // 여전히 마지막 스텝
        #expect(progress.nextStep == nil)
    }

    // MARK: - 남은 거리 단조 감소

    @Test func remainingDistance_decreases() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        let pos1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.002)
        let progress1 = tracker.update(matchedPosition: pos1)

        let pos2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.004)
        let progress2 = tracker.update(matchedPosition: pos2)

        #expect(progress2.remainingDistance < progress1.remainingDistance)
    }

    // MARK: - 남은 시간 (카카오: duration 합산)

    @Test func remainingTime_kakao_usesDuration() {
        let tracker = RouteTracker(route: Self.makeTestRoute(provider: .kakao))

        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress = tracker.update(matchedPosition: pos)

        // Step 0 duration(100) + Step 1(100) + Step 2(100) = 300초
        #expect(progress.remainingTime > 200)
        #expect(progress.remainingTime <= 300)
    }

    // MARK: - 남은 시간 (Apple: 거리 비율)

    @Test func remainingTime_apple_usesDistanceRatio() {
        let tracker = RouteTracker(route: Self.makeTestRoute(provider: .apple))

        // 경로 중간 지점
        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.007)
        let progress = tracker.update(matchedPosition: pos)

        // 전체 300초, 남은 거리 비율로 추정 → 0보다 크고 300보다 작음
        #expect(progress.remainingTime > 0)
        #expect(progress.remainingTime < 300)
    }

    // MARK: - ETA 계산

    @Test func eta_isFuture() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress = tracker.update(matchedPosition: pos)

        #expect(progress.eta > Date())
    }

    // MARK: - distanceToNextManeuver

    @Test func distanceToNextManeuver_decreasesWithProgress() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        let pos1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress1 = tracker.update(matchedPosition: pos1)

        let pos2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.003)
        let progress2 = tracker.update(matchedPosition: pos2)

        #expect(progress2.distanceToNextManeuver < progress1.distanceToNextManeuver)
    }

    // MARK: - 스텝 전진 콜백

    @Test func stepAdvanceCallback_fires() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        var advancedFrom: Int?
        var advancedTo: Int?
        tracker.onStepAdvance = { from, to, _ in
            advancedFrom = from
            advancedTo = to
        }

        let nearG0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.00498)
        _ = tracker.update(matchedPosition: nearG0)

        #expect(advancedFrom == 0)
        #expect(advancedTo == 1)
    }

    // MARK: - 리셋

    @Test func reset_goesBackToStep0() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // Step 0 → 1 전진
        let nearG0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.00498)
        _ = tracker.update(matchedPosition: nearG0)
        #expect(tracker.currentStepIndex == 1)

        // 리셋
        tracker.reset()
        #expect(tracker.currentStepIndex == 0)
    }
}
