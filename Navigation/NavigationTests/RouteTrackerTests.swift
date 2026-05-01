import Testing
import CoreLocation
@testable import Navigation

struct RouteTrackerTests {

    // MARK: - Test Route

    /// P0(37.5, 127.0) → G0(37.5, 127.005) → G1(37.5, 127.01) → G2(37.5, 127.015)
    /// 4개 폴리라인 점, 3스텝
    /// Step 0: 출발지 (1pt — 스킵 대상)
    /// Step 1: P0→G0 직진
    /// Step 2: G0→G1 우회전
    /// Step 3: G1→G2 목적지
    static func makeTestRoute(provider: RouteProvider = .kakao) -> Route {
        let p0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0)
        let g0 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005)
        let g1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.01)
        let g2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.015)

        return Route(
            id: "test",
            distance: 1500,
            expectedTravelTime: 300,
            name: "테스트",
            steps: [
                RouteStep(
                    instructions: "출발지",
                    distance: 0,
                    polylineCoordinates: [p0],  // 1pt — 출발지 마커
                    duration: 0,
                    turnType: .straight,
                    roadName: "출발지"
                ),
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

    // MARK: - 출발지 스킵

    @Test func skips_departureStep() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // Step 0 (출발지, 1pt)이 스킵되어 Step 1부터 시작
        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress = tracker.update(matchedPosition: pos, segmentIndex: 0)

        #expect(progress.currentStepIndex == 1)
        #expect(progress.currentStep.instructions == "직진")
    }

    // MARK: - segmentIndex 기반 전진

    @Test func advancesStep_whenSegmentIndexPassesStepEnd() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // segmentIndex=0: Step 1 범위 (P0→G0)
        let pos1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.003)
        let progress1 = tracker.update(matchedPosition: pos1, segmentIndex: 0)
        #expect(progress1.currentStepIndex == 1)

        // segmentIndex=1: Step 1의 끝(G0)을 지남 → Step 2로 전진
        let pos2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.006)
        let progress2 = tracker.update(matchedPosition: pos2, segmentIndex: 1)
        #expect(progress2.currentStepIndex == 2)
        #expect(progress2.currentStep.instructions == "우회전")
    }

    // MARK: - 마지막 스텝에서 전진 안 함

    @Test func doesNotAdvancePastLastStep() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // segmentIndex=2: Step 2의 끝(G1)을 지남 → Step 3
        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.012)
        _ = tracker.update(matchedPosition: pos, segmentIndex: 2)
        #expect(tracker.currentStepIndex == 3)

        // segmentIndex=2: 마지막 스텝에서 더 전진하지 않음
        let pos2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.014)
        let progress = tracker.update(matchedPosition: pos2, segmentIndex: 2)
        #expect(progress.currentStepIndex == 3)
        #expect(progress.nextStep == nil)
    }

    // MARK: - 남은 거리 감소

    @Test func remainingDistance_decreases() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        let pos1 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.002)
        let progress1 = tracker.update(matchedPosition: pos1, segmentIndex: 0)

        let pos2 = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.004)
        let progress2 = tracker.update(matchedPosition: pos2, segmentIndex: 0)

        #expect(progress2.remainingDistance < progress1.remainingDistance)
    }

    // MARK: - 남은 시간 (카카오)

    @Test func remainingTime_kakao_usesDuration() {
        let tracker = RouteTracker(route: Self.makeTestRoute(provider: .kakao))

        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress = tracker.update(matchedPosition: pos, segmentIndex: 0)

        // Step 1(100) + Step 2(100) + Step 3(100) = 300초
        #expect(progress.remainingTime > 200)
        #expect(progress.remainingTime <= 300)
    }

    // MARK: - 남은 시간 (Apple)

    @Test func remainingTime_apple_usesDistanceRatio() {
        let tracker = RouteTracker(route: Self.makeTestRoute(provider: .apple))

        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.007)
        let progress = tracker.update(matchedPosition: pos, segmentIndex: 1)

        #expect(progress.remainingTime > 0)
        #expect(progress.remainingTime < 300)
    }

    // MARK: - ETA

    @Test func eta_isFuture() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let progress = tracker.update(matchedPosition: pos, segmentIndex: 0)

        #expect(progress.eta > Date())
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

        // segmentIndex=1 → Step 1 끝 통과 → Step 2로 전진
        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.006)
        _ = tracker.update(matchedPosition: pos, segmentIndex: 1)

        #expect(advancedFrom == 1)
        #expect(advancedTo == 2)
    }

    // MARK: - 리셋

    @Test func reset_goesBackToStep1_afterDepartureSkip() {
        let tracker = RouteTracker(route: Self.makeTestRoute())

        // Step 2로 전진
        let pos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.006)
        _ = tracker.update(matchedPosition: pos, segmentIndex: 1)
        #expect(tracker.currentStepIndex == 2)

        // 리셋 → 출발지 스킵 → Step 1
        tracker.reset()
        #expect(tracker.currentStepIndex == 1)
    }
}
