import Testing
import CoreLocation
@testable import Navigation

struct StateManagerTests {

    // MARK: - 초기 상태

    @Test func initialState_isPreparing() {
        let sm = StateManager()
        #expect(sm.state == .preparing)
    }

    // MARK: - preparing → navigating

    @Test func preparing_toNavigating_onFirstMatch() {
        let sm = StateManager()

        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)

        #expect(sm.state == .navigating)
    }

    @Test func preparing_stays_whenNotMatched() {
        let sm = StateManager()

        sm.update(isMatched: false, isOffRoute: false, distanceToGoal: 5000)

        #expect(sm.state == .preparing)
    }

    // MARK: - navigating → arrived

    @Test func navigating_toArrived_when30mOrLess() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)  // → navigating

        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 25)

        #expect(sm.state == .arrived)
    }

    // MARK: - navigating → rerouting

    @Test func navigating_toRerouting_whenOffRoute() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)  // → navigating

        sm.update(isMatched: false, isOffRoute: true, distanceToGoal: 5000)

        #expect(sm.state == .rerouting)
    }

    // MARK: - navigating → stopped

    @Test func navigating_toStopped_onUserStop() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)  // → navigating

        sm.stop()

        #expect(sm.state == .stopped)
    }

    // MARK: - rerouting → navigating (성공)

    @Test func rerouting_toNavigating_onRerouteSuccess() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)  // → navigating
        sm.update(isMatched: false, isOffRoute: true, distanceToGoal: 5000)  // → rerouting

        sm.rerouteSucceeded()

        #expect(sm.state == .navigating)
    }

    // MARK: - rerouting → navigating (실패)

    @Test func rerouting_toNavigating_onRerouteFailed() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)
        sm.update(isMatched: false, isOffRoute: true, distanceToGoal: 5000)

        sm.rerouteFailed()

        #expect(sm.state == .navigating)
    }

    // MARK: - rerouting → arrived (재탐색 중 도착)

    @Test func rerouting_toArrived_whenNearGoal() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)
        sm.update(isMatched: false, isOffRoute: true, distanceToGoal: 5000)  // → rerouting

        sm.update(isMatched: false, isOffRoute: false, distanceToGoal: 20)

        #expect(sm.state == .arrived)
    }

    // MARK: - arrived → stopped

    @Test func arrived_toStopped_onFinishArrival() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 25)  // → arrived

        sm.finishArrival()

        #expect(sm.state == .stopped)
    }

    // MARK: - arrived/stopped은 최종 상태

    @Test func arrived_doesNotChange_onUpdate() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 25)  // → arrived

        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)

        #expect(sm.state == .arrived)  // 변하지 않음
    }

    @Test func stopped_doesNotChange_onUpdate() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)
        sm.stop()

        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)

        #expect(sm.state == .stopped)
    }

    // MARK: - 수동 재탐색

    @Test func requestReroute_fromNavigating() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)

        sm.requestReroute()

        #expect(sm.state == .rerouting)
    }

    @Test func requestReroute_ignoredIfNotNavigating() {
        let sm = StateManager()
        // preparing 상태에서는 무시
        sm.requestReroute()

        #expect(sm.state == .preparing)
    }

    // MARK: - 상태 전이 콜백

    @Test func stateChangeCallback_fires() {
        let sm = StateManager()

        var fromState: NavigationState?
        var toState: NavigationState?
        sm.onStateChange = { from, to in
            fromState = from
            toState = to
        }

        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)

        #expect(fromState == .preparing)
        #expect(toState == .navigating)
    }

    // MARK: - 리셋

    @Test func reset_goesBackToPreparing() {
        let sm = StateManager()
        sm.update(isMatched: true, isOffRoute: false, distanceToGoal: 5000)
        #expect(sm.state == .navigating)

        sm.reset()
        #expect(sm.state == .preparing)
    }
}
