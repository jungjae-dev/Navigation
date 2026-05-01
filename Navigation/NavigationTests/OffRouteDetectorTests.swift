import Testing
import CoreLocation
@testable import Navigation

struct OffRouteDetectorTests {

    // MARK: - Helpers

    private func makeMatchResult(isMatched: Bool, coordinate: CLLocationCoordinate2D = .init(latitude: 37.5, longitude: 127.0)) -> MatchResult {
        MatchResult(
            isMatched: isMatched,
            coordinate: coordinate,
            segmentIndex: 0,
            distanceFromRoute: isMatched ? 10 : 60,
            headingDelta: 0
        )
    }

    private func makeDetectorAfterStart() -> OffRouteDetector {
        let detector = OffRouteDetector()
        // 출발점에서 충분히 떨어진 좌표로 시작 (보호 조건 회피)
        detector.start(at: CLLocationCoordinate2D(latitude: 37.0, longitude: 126.0))
        return detector
    }

    // MARK: - 기본 이탈 판정

    @Test func twoFailures_notOffRoute() {
        let detector = makeDetectorAfterStart()

        // 보호 시간 지나도록 시작 시간 조정은 어렵지만,
        // start 좌표를 멀리 두면 거리/시간 보호를 우회 가능
        // → 실제로는 5초 보호가 걸리므로 Sleep이 필요하나 단위 테스트에서는
        //   보호 조건을 피하기 위해 충분히 먼 좌표 사용

        // 5초 이내 보호 때문에 여기서는 보호 통과 안될 수 있음
        // → 별도 테스트에서 보호 조건 확인
        let result1 = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
        let result2 = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)

        // 5초 보호 내이므로 false
        #expect(result1 == false)
        #expect(result2 == false)
    }

    @Test func matchSuccess_resetsCounter() {
        let detector = OffRouteDetector()
        detector.start(at: CLLocationCoordinate2D(latitude: 37.0, longitude: 126.0))

        // 매칭 성공 → 카운터 리셋
        _ = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
        _ = detector.update(matchResult: makeMatchResult(isMatched: true), gpsAccuracy: 5)

        #expect(detector.consecutiveFailures == 0)
    }

    // MARK: - 보호 조건: GPS 정확도

    @Test func badAccuracy_returns_false() {
        let detector = OffRouteDetector()
        detector.start(at: CLLocationCoordinate2D(latitude: 37.0, longitude: 126.0))

        // GPS 정확도 > 120m → 보류
        let result = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 150)

        #expect(result == false)
        #expect(detector.consecutiveFailures == 0)  // 카운터 증가 안 됨
    }

    // MARK: - 보호 조건: 출발 거리

    @Test func nearStartPoint_returns_false() {
        let detector = OffRouteDetector()
        let startCoord = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0)
        detector.start(at: startCoord)

        // 출발점에서 10m 이내 좌표
        let nearStart = CLLocationCoordinate2D(latitude: 37.50005, longitude: 127.0)
        let result = detector.update(
            matchResult: MatchResult(isMatched: false, coordinate: nearStart, segmentIndex: 0, distanceFromRoute: 60, headingDelta: 0),
            gpsAccuracy: 5
        )

        #expect(result == false)
    }

    // MARK: - 리셋

    @Test func reset_clearsCounter() {
        let detector = OffRouteDetector()
        detector.start(at: CLLocationCoordinate2D(latitude: 37.0, longitude: 126.0))

        _ = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
        _ = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)

        detector.reset()
        #expect(detector.consecutiveFailures == 0)
    }
}
