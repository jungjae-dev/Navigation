import Testing
import CoreLocation
@testable import Navigation

struct DeadReckoningTests {

    // MARK: - Test Polyline

    // P0(37.5, 127.0) → P1(37.5, 127.005) → P2(37.5, 127.01)
    // 각 세그먼트 약 430m (동쪽 방향)
    static let testPolyline: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
        CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005),
        CLLocationCoordinate2D(latitude: 37.5, longitude: 127.01),
    ]

    // MARK: - 기본 추정

    @Test func estimate_advancesOnPolyline() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startPos = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0)
        let startTime = Date()

        dr.updateLastValid(position: startPos, speed: 22.2, segmentIndex: 0)  // 80km/h

        // 1초 후 → 22.2m 전진
        let result = dr.estimate(currentTime: startTime.addingTimeInterval(1))

        #expect(result != nil)
        // 전진했으므로 longitude가 증가해야 함
        #expect(result!.coordinate.longitude > 127.0)
        #expect(result!.segmentIndex == 0)
    }

    // MARK: - 3초 추정 (66.6m)

    @Test func estimate_3seconds() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startTime = Date()
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 22.2,
            segmentIndex: 0
        )

        let result = dr.estimate(currentTime: startTime.addingTimeInterval(3))

        #expect(result != nil)
        // 66.6m 전진 → 430m 세그먼트 내
        #expect(result!.segmentIndex == 0)
        #expect(result!.coordinate.longitude > 127.0)
    }

    // MARK: - 세그먼트 경계 넘기

    @Test func estimate_crossesSegmentBoundary() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startTime = Date()
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 22.2,
            segmentIndex: 0
        )

        // 430m 세그먼트를 넘을 만큼 오래 경과 → 약 20초 (444m)
        let result = dr.estimate(currentTime: startTime.addingTimeInterval(20))

        #expect(result != nil)
        #expect(result!.segmentIndex == 1)  // 두 번째 세그먼트로 전진
    }

    // MARK: - 폴리라인 끝 도달

    @Test func estimate_reachesEndOfPolyline() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startTime = Date()
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 22.2,
            segmentIndex: 0
        )

        // 매우 긴 시간 → 폴리라인 끝 도달
        let result = dr.estimate(currentTime: startTime.addingTimeInterval(100))

        #expect(result != nil)
        // 마지막 좌표에 도달
        #expect(abs(result!.coordinate.longitude - 127.01) < 0.001)
    }

    // MARK: - heading = 세그먼트 방향

    @Test func estimate_headingMatchesSegmentDirection() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startTime = Date()
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 22.2,
            segmentIndex: 0
        )

        let result = dr.estimate(currentTime: startTime.addingTimeInterval(1))

        #expect(result != nil)
        // 동쪽 방향 → heading ≈ 90°
        #expect(result!.heading > 80 && result!.heading < 100)
    }

    // MARK: - 속도 0이면 추정 안 함

    @Test func estimate_zeroSpeed_returnsNil() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startTime = Date()
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 0,  // 정지
            segmentIndex: 0
        )

        let result = dr.estimate(currentTime: startTime.addingTimeInterval(1))

        #expect(result == nil)
    }

    // MARK: - updateLastValid 후 리셋

    @Test func updateLastValid_resetsAccumulation() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let startTime = Date()
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 22.2,
            segmentIndex: 0
        )

        // 1초 후 추정
        let result1 = dr.estimate(currentTime: startTime.addingTimeInterval(1))
        #expect(result1 != nil)

        // 새 유효 위치로 갱신
        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.005),
            speed: 22.2,
            segmentIndex: 1
        )

        // 새 위치 기준으로 1초 후 추정
        let newTime = Date()
        let result2 = dr.estimate(currentTime: newTime.addingTimeInterval(1))

        #expect(result2 != nil)
        #expect(result2!.segmentIndex == 1)  // 새 세그먼트에서 시작
    }

    // MARK: - advanceOnPolyline 직접 테스트

    @Test func advanceOnPolyline_100m() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        let result = dr.advanceOnPolyline(fromSegmentIndex: 0, distance: 100)

        #expect(result != nil)
        #expect(result!.segmentIndex == 0)
        #expect(result!.coordinate.longitude > 127.0)
        #expect(result!.coordinate.longitude < 127.005)
    }

    // MARK: - 리셋

    @Test func reset_clearsState() {
        let dr = DeadReckoning(polyline: Self.testPolyline)

        dr.updateLastValid(
            position: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            speed: 22.2,
            segmentIndex: 0
        )

        dr.reset()

        let result = dr.estimate(currentTime: Date().addingTimeInterval(1))
        #expect(result == nil)  // 리셋 후 추정 불가
    }
}
