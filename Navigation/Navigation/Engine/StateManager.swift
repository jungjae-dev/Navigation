import CoreLocation

/// 네비게이션 상태 머신
/// preparing → navigating → arrived / rerouting / stopped
final class StateManager {

    // MARK: - Configuration

    private let arrivalThreshold: CLLocationDistance = 30  // 도착 판정 (m)

    // MARK: - State

    private(set) var state: NavigationState = .preparing

    /// 상태 전이 콜백 (로그용)
    var onStateChange: ((_ from: NavigationState, _ to: NavigationState) -> Void)?

    // MARK: - Update

    /// 매 틱마다 호출하여 상태 전이 판정
    /// - Parameters:
    ///   - isMatched: 맵매칭 성공 여부 (GPS invalid 시 true로 전달 — DR 좌표 사용)
    ///   - isOffRoute: 이탈 확정 여부
    ///   - distanceToGoal: 목적지까지 남은 거리 (RouteProgress.remainingDistance)
    @discardableResult
    func update(
        isMatched: Bool,
        isOffRoute: Bool,
        distanceToGoal: CLLocationDistance
    ) -> NavigationState {
        let previousState = state

        switch state {
        case .preparing:
            if isMatched {
                state = .navigating
            }

        case .navigating:
            if distanceToGoal <= arrivalThreshold {
                state = .arrived
            } else if isOffRoute {
                state = .rerouting
            }

        case .rerouting:
            // 재탐색 중에도 도착 판정
            if distanceToGoal <= arrivalThreshold {
                state = .arrived
            }
            // 새 경로 수신 / 실패 시 → navigating 복귀는 외부에서 호출
            // rerouteSucceeded() / rerouteFailed()

        case .arrived, .stopped:
            break  // 최종 상태
        }

        if state != previousState {
            onStateChange?(previousState, state)
        }

        return state
    }

    // MARK: - External Transitions

    /// 재탐색 성공 → navigating 복귀
    func rerouteSucceeded() {
        guard state == .rerouting else { return }
        let previous = state
        state = .navigating
        onStateChange?(previous, state)
    }

    /// 재탐색 실패 (3회 모두 실패) → navigating 복귀 (이전 경로 유지)
    func rerouteFailed() {
        guard state == .rerouting else { return }
        let previous = state
        state = .navigating
        onStateChange?(previous, state)
    }

    /// 사용자 안내 종료
    func stop() {
        let previous = state
        state = .stopped
        if state != previous {
            onStateChange?(previous, state)
        }
    }

    /// 도착 후 종료 (5초 타이머 또는 버튼)
    func finishArrival() {
        guard state == .arrived else { return }
        let previous = state
        state = .stopped
        onStateChange?(previous, state)
    }

    /// 수동 재탐색 요청
    func requestReroute() {
        guard state == .navigating else { return }
        let previous = state
        state = .rerouting
        onStateChange?(previous, state)
    }

    /// 리셋
    func reset() {
        state = .preparing
    }
}
