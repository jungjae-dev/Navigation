import Testing
import CoreLocation
import Combine
@testable import Navigation

/// NavigationEngine: 매칭 실패 시 DR 폴백 동작 검증
/// - isMatched=false + DR 데이터 있음 → matchedPosition = DR 추정 좌표 (rawGPS 아님)
/// - isMatched=true              → matchedPosition = snapped 좌표
struct NavigationEngineDRFallbackTests {

    // 동쪽으로 직선 경로: lat=37.5 고정, lon 127.000 → 127.010
    // 각 세그먼트 약 860m
    static let polyline: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 37.5000, longitude: 127.000),
        CLLocationCoordinate2D(latitude: 37.5000, longitude: 127.005),
        CLLocationCoordinate2D(latitude: 37.5000, longitude: 127.010),
    ]

    static let route = Route(
        id: "dr-test",
        distance: 1720,
        expectedTravelTime: 120,
        name: "DR 테스트 경로",
        steps: [
            RouteStep(
                instructions: "직진",
                distance: 1720,
                polylineCoordinates: polyline,
                duration: 120,
                turnType: .straight,
                roadName: "테스트로"
            )
        ],
        polylineCoordinates: polyline,
        transportMode: .automobile,
        provider: .kakao
    )

    // MARK: - Helpers

    /// 경로 위 GPS: lat=37.5, course=90°(동쪽), speed=15m/s
    private func onRouteLocation(lon: Double = 127.0025) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.5000, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: 15,
            timestamp: Date()
        )
    }

    /// 경로 밖 GPS: lat=37.5006 (약 67m 북쪽, threshold 50m 초과)
    private func offRouteLocation(lon: Double = 127.0025) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.5006, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: 15,
            timestamp: Date()
        )
    }

    private func makeEngine() -> NavigationEngine {
        let engine = NavigationEngine(
            route: Self.route,
            transportMode: .automobile,
            routeService: MockRouteService()
        )
        engine.setStartCoordinate(Self.polyline[0])
        return engine
    }

    // MARK: - 매칭 성공 시 snapped 좌표 사용

    @Test func matchSuccess_usesSnappedPosition() {
        let engine = makeEngine()

        engine.tick(location: onRouteLocation())

        let guide = engine.guidePublisher.value
        #expect(guide?.isMatched == true)

        // 경로 위(lat≈37.5)에 스냅되어야 함
        let lat = guide?.matchedPosition.latitude ?? 0
        #expect(abs(lat - 37.5) < 0.0001, "스냅 좌표가 경로(37.5) 위여야 함, 실제: \(lat)")
    }

    // MARK: - 매칭 실패 시 DR 폴백 (핵심 검증)

    @Test func matchFailure_withDRData_usesDRNotRawGPS() {
        let engine = makeEngine()

        // tick 1: 경로 위 GPS → 매칭 성공, DR 데이터 갱신
        engine.tick(location: onRouteLocation())
        let snappedLat = engine.guidePublisher.value?.matchedPosition.latitude ?? 0
        #expect(abs(snappedLat - 37.5) < 0.0001)

        // tick 2: 경로 밖 GPS (67m 이탈) → 매칭 실패
        let offLocation = offRouteLocation()
        engine.tick(location: offLocation)
        let guide = engine.guidePublisher.value

        #expect(guide?.isMatched == false, "경로 밖 GPS는 isMatched=false여야 함")

        let pos = guide!.matchedPosition
        let rawLat = offLocation.coordinate.latitude  // 37.5006

        // DR 폴백: matchedPosition이 경로(37.5) 근처여야 함
        #expect(abs(pos.latitude - snappedLat) < 0.0005,
                "DR 폴백 실패: matchedPosition.lat=\(pos.latitude), 기대값≈\(snappedLat)")

        // rawGPS 위치(37.5006)와는 달라야 함
        #expect(abs(pos.latitude - rawLat) > 0.0003,
                "rawGPS를 그대로 쓰면 안 됨: matchedPosition.lat=\(pos.latitude), rawGPS.lat=\(rawLat)")
    }

    // MARK: - DR 데이터 없을 때 rawGPS 최후 수단

    @Test func matchFailure_withoutDRData_fallsBackToRawGPS() {
        let engine = makeEngine()

        // DR 데이터 없이 (tick 1 없이) 바로 경로 밖 GPS
        let offLocation = offRouteLocation()
        engine.tick(location: offLocation)
        let guide = engine.guidePublisher.value

        #expect(guide?.isMatched == false)

        let pos = guide!.matchedPosition
        let rawLat = offLocation.coordinate.latitude

        // DR 없음 → rawGPS 최후 수단 사용
        #expect(abs(pos.latitude - rawLat) < 0.0001,
                "DR 없을 때는 rawGPS 사용: \(pos.latitude) vs \(rawLat)")
    }

    // MARK: - 매칭 성공 후 연속 실패 시 DR이 계속 경로 위 유지

    @Test func consecutiveMatchFailures_drKeepsPositionOnRoute() {
        let engine = makeEngine()

        // tick 1: 매칭 성공 → DR 갱신
        engine.tick(location: onRouteLocation())

        // tick 2~4: 연속 매칭 실패 (OffRouteDetector 5회 미만 → 재탐색 안 됨)
        for _ in 2...4 {
            engine.tick(location: offRouteLocation())
            let guide = engine.guidePublisher.value
            let lat = guide?.matchedPosition.latitude ?? 0

            // 매칭 실패지만 DR로 경로(lat≈37.5) 위에 머물러야 함
            #expect(abs(lat - 37.5) < 0.0005,
                    "연속 실패 중에도 DR로 경로 위 유지되어야 함: lat=\(lat)")
        }
    }
}
