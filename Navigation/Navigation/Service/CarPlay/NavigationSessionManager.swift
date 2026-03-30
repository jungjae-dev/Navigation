import Foundation
import Combine
import CoreLocation

// MARK: - Navigation Session (stub — 새 엔진 구현 시 교체 예정)

struct NavigationSession {
    let route: Route
    let destination: Place
}

// MARK: - Navigation Command

enum NavigationSource {
    case phone
    case carPlay
}

enum NavigationCommand {
    case started(source: NavigationSource)
    case stopped
}

// MARK: - NavigationSessionManager

final class NavigationSessionManager {

    static let shared = NavigationSessionManager()

    // MARK: - Publishers

    let activeSessionPublisher = CurrentValueSubject<NavigationSession?, Never>(nil)
    let navigationCommandPublisher = PassthroughSubject<NavigationCommand, Never>()

    // MARK: - Init

    private init() {}

    // MARK: - Public

    var isNavigating: Bool {
        activeSessionPublisher.value != nil
    }

    func startNavigation(
        route: Route,
        destination: Place,
        source: NavigationSource
    ) {
        if isNavigating {
            stopNavigation()
        }

        let session = NavigationSession(
            route: route,
            destination: destination
        )

        activeSessionPublisher.send(session)
        navigationCommandPublisher.send(.started(source: source))

        print("[TODO] NavigationEngine 생성 및 연결 예정")
    }

    func stopNavigation() {
        activeSessionPublisher.send(nil)
        navigationCommandPublisher.send(.stopped)
    }
}
