import UIKit
import CarPlay
import CoreLocation
import Combine

// stub — 새 NavigationEngine 구현 시 교체 예정
final class CarPlayNavigationHandler {

    // MARK: - Properties

    private var navigationSession: CPNavigationSession?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public

    func startNavigation(
        trip: CPTrip,
        mapTemplate: CPMapTemplate
    ) {
        stopNavigation()

        let session = mapTemplate.startNavigationSession(for: trip)
        session.pauseTrip(for: .loading, description: "경로 준비 중", turnCardColor: nil)
        self.navigationSession = session

        // TODO: 새 NavigationEngine의 guidePublisher 구독으로 교체 예정
        print("[TODO] CarPlayNavigationHandler - 새 엔진 guidePublisher 구독 예정")
    }

    func stopNavigation() {
        cancellables.removeAll()
        navigationSession?.finishTrip()
        navigationSession = nil
    }
}
