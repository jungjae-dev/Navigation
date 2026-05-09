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
            headingDelta: 0,
            score: isMatched ? 10 : 60
        )
    }

    private func makeDetectorAfterStart() -> OffRouteDetector {
        let detector = OffRouteDetector()
        // 출발점에서 충분히 떨어진 좌표로 시작 (보호 조건 회피)
        detector.start(at: CLLocationCoordinate2D(latitude: 37.0, longitude: 126.0))
        return detector
    }

    // MARK: - 연속 실패 카운트 (보호 조건 없는 상태로 검증)
    // start()를 호출하지 않으면 navigationStartTime=nil, startCoordinate=nil →
    // 시간/거리 보호 조건 스킵, 카운터 로직만 순수하게 테스트 가능

    @Test func twoConsecutiveFailures_notOffRoute() {
        let detector = OffRouteDetector()  // start() 미호출 → 보호 조건 없음

        for i in 1...2 {
            let result = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
            #expect(result == false, "실패 \(i)회 차에 이탈 확정되면 안 됨")
        }
        #expect(detector.consecutiveFailures == 2)
    }

    @Test func threeConsecutiveFailures_triggersOffRoute() {
        let detector = OffRouteDetector()

        for _ in 1...2 {
            _ = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
        }
        let result = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)

        #expect(result == true, "3회 연속 실패 시 이탈 확정되어야 함")
        #expect(detector.consecutiveFailures == 3)
    }

    @Test func successInMiddle_resetsCounter_requiresThreeAgain() {
        let detector = OffRouteDetector()

        // 2번 실패
        for _ in 1...2 {
            _ = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
        }
        #expect(detector.consecutiveFailures == 2)

        // 1번 성공 → 카운터 리셋
        _ = detector.update(matchResult: makeMatchResult(isMatched: true), gpsAccuracy: 5)
        #expect(detector.consecutiveFailures == 0)

        // 리셋 후 다시 2번 실패해도 이탈 미확정
        for _ in 1...2 {
            let result = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
            #expect(result == false, "리셋 후 2회는 이탈 확정 안됨")
        }
    }

    @Test func twoFailures_notOffRoute() {
        let detector = makeDetectorAfterStart()

        // start() 직후 5초 보호 내 → 모두 false
        let result1 = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)
        let result2 = detector.update(matchResult: makeMatchResult(isMatched: false), gpsAccuracy: 5)

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
            matchResult: MatchResult(isMatched: false, coordinate: nearStart, segmentIndex: 0, distanceFromRoute: 60, headingDelta: 0, score: 60),
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
