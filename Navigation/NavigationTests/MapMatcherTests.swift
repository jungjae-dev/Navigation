import Testing
import CoreLocation
@testable import Navigation

struct MapMatcherTests {

    // MARK: - Test Polyline (서쪽→동쪽 직선 경로, ~1km)

    // P0(37.5, 127.0) → P1(37.5, 127.005) → P2(37.5, 127.01)
    // 약 동쪽 방향 (heading ≈ 90°)
    static let straightPolyline: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
        CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005),
        CLLocationCoordinate2D(latitude: 37.5, longitude: 127.01),
    ]

    // MARK: - 매칭 성공 (경로 위)

    @Test func matchOnRoute_success() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0025),
            heading: 90,
            speed: 15,
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == true)
        #expect(result.distanceFromRoute < 10)  // 경로 위이므로 거의 0m
        #expect(result.segmentIndex == 0)
    }

    // MARK: - 매칭 성공 (경로 근처, < 50m)

    @Test func matchNearRoute_withinThreshold() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        // 경로에서 약 30m 북쪽
        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.50027, longitude: 127.0025),
            heading: 90,
            speed: 15,
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == true)
        #expect(result.distanceFromRoute < 50)
        #expect(result.distanceFromRoute > 10)
    }

    // MARK: - 매칭 실패 (경로에서 60m 이상)

    @Test func matchFarFromRoute_fails() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        // 경로에서 약 60m 북쪽
        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.50055, longitude: 127.0025),
            heading: 90,
            speed: 15,
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == false)
        #expect(result.distanceFromRoute > 50)
    }

    // MARK: - 방향 검증 실패 (역방향)

    @Test func matchReverseHeading_failsForAutomobile() {
        let matcher = MapMatcher(polyline: Self.straightPolyline, transportMode: .automobile)

        // 경로 위이지만 역방향 (heading = 270°, 경로는 90°)
        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0025),
            heading: 270,
            speed: 15,
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == false)
        #expect(result.headingDelta > 90)
    }

    // MARK: - 도보 모드에서 역방향도 매칭 성공

    @Test func matchReverseHeading_succeedsForWalking() {
        let matcher = MapMatcher(polyline: Self.straightPolyline, transportMode: .walking)

        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0025),
            heading: 270,
            speed: 1.0,
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == true)  // 도보 → 방향 검증 스킵
    }

    // MARK: - 저속에서 방향 검증 스킵

    @Test func matchLowSpeed_skipsHeadingCheck() {
        let matcher = MapMatcher(polyline: Self.straightPolyline, transportMode: .automobile)

        // 자동차 모드이지만 저속 (< 1.4 m/s = 5km/h)
        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0025),
            heading: 270,  // 역방향
            speed: 1.0,    // 저속
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == true)  // 저속 → 방향 검증 스킵
    }

    // MARK: - segmentIndex 전진

    @Test func segmentIndex_advances() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        // 첫 번째 세그먼트 위
        let gps1 = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.002),
            heading: 90, speed: 15, accuracy: 5, timestamp: Date(), isValid: true
        )
        let result1 = matcher.match(gps1)
        #expect(result1.segmentIndex == 0)

        // 두 번째 세그먼트 위
        let gps2 = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.007),
            heading: 90, speed: 15, accuracy: 5, timestamp: Date(), isValid: true
        )
        let result2 = matcher.match(gps2)
        #expect(result2.segmentIndex == 1)

        // currentSegmentIndex가 갱신되었는지
        #expect(matcher.currentSegmentIndex == 1)
    }

    // MARK: - 투영점 계산 (수선의 발)

    @Test func projectPointOnSegment_perpendicular() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        // P0(37.5, 127.0) → P1(37.5, 127.005) 세그먼트에
        // (37.5003, 127.0025)를 투영 → (37.5, 127.0025) 근처
        let (projection, distance) = matcher.projectPointOnSegment(
            point: CLLocationCoordinate2D(latitude: 37.5003, longitude: 127.0025),
            segStart: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            segEnd: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005)
        )

        // 투영점은 경로 위 (latitude ≈ 37.5)
        #expect(abs(projection.latitude - 37.5) < 0.0001)
        // 투영점의 longitude는 원래 점과 비슷
        #expect(abs(projection.longitude - 127.0025) < 0.001)
        // 거리 > 0 (경로에서 떨어져 있으므로)
        #expect(distance > 10)
        #expect(distance < 50)
    }

    @Test func projectPointOnSegment_beforeStart() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        // 세그먼트 시작점 이전 → 시작점에 클램핑
        let (projection, _) = matcher.projectPointOnSegment(
            point: CLLocationCoordinate2D(latitude: 37.5, longitude: 126.999),
            segStart: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            segEnd: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005)
        )

        #expect(abs(projection.longitude - 127.0) < 0.0001)
    }

    @Test func projectPointOnSegment_afterEnd() {
        let matcher = MapMatcher(polyline: Self.straightPolyline)

        // 세그먼트 끝점 이후 → 끝점에 클램핑
        let (projection, _) = matcher.projectPointOnSegment(
            point: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.006),
            segStart: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            segEnd: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005)
        )

        #expect(abs(projection.longitude - 127.005) < 0.0001)
    }

    // MARK: - 빈 폴리라인

    @Test func emptyPolyline_fails() {
        let matcher = MapMatcher(polyline: [])

        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            heading: 0, speed: 0, accuracy: 5, timestamp: Date(), isValid: true
        )

        let result = matcher.match(gps)
        #expect(result.isMatched == false)
    }

    // MARK: - 꺾이는 경로 (L자형)

    @Test func lShapedRoute_matchesCorrectSegment() {
        // P0(37.5, 127.0) → P1(37.5, 127.005) → P2(37.505, 127.005)
        // 동쪽 → 북쪽으로 꺾임
        let lPolyline = [
            CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005),
            CLLocationCoordinate2D(latitude: 37.505, longitude: 127.005),
        ]
        let matcher = MapMatcher(polyline: lPolyline)

        // 두 번째 세그먼트(북쪽 방향) 위 점
        let gps = GPSData(
            coordinate: CLLocationCoordinate2D(latitude: 37.502, longitude: 127.005),
            heading: 0,  // 북쪽
            speed: 15,
            accuracy: 5,
            timestamp: Date(),
            isValid: true
        )

        let result = matcher.match(gps)

        #expect(result.isMatched == true)
        #expect(result.segmentIndex == 1)
    }
}
