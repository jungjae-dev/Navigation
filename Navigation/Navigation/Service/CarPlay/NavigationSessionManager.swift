import Foundation
import Combine
import MapKit
import CoreLocation

// MARK: - Navigation Session

struct NavigationSession {
    let route: MKRoute
    let destination: MKMapItem
    let guidanceEngine: GuidanceEngine
    let voiceService: VoiceGuidanceService
    let offRouteDetector: OffRouteDetector
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

    // MARK: - Dependencies

    private let locationService = LocationService.shared
    private let routeService = RouteService()

    // MARK: - Init

    private init() {}

    // MARK: - Public

    var isNavigating: Bool {
        activeSessionPublisher.value != nil
    }

    func startNavigation(
        route: MKRoute,
        destination: MKMapItem,
        source: NavigationSource
    ) {
        // Stop existing session if any
        if isNavigating {
            stopNavigation()
        }

        // Create shared services
        let voiceService = VoiceGuidanceService()
        let offRouteDetector = OffRouteDetector()

        let guidanceEngine = GuidanceEngine(
            locationService: locationService,
            routeService: routeService,
            voiceService: voiceService,
            offRouteDetector: offRouteDetector
        )

        let session = NavigationSession(
            route: route,
            destination: destination,
            guidanceEngine: guidanceEngine,
            voiceService: voiceService,
            offRouteDetector: offRouteDetector
        )

        // Configure location for navigation
        locationService.configureForNavigation()

        // Start guidance
        guidanceEngine.startNavigation(with: route)

        // Publish
        activeSessionPublisher.send(session)
        navigationCommandPublisher.send(.started(source: source))
    }

    func stopNavigation() {
        guard let session = activeSessionPublisher.value else { return }

        session.guidanceEngine.stopNavigation()
        session.voiceService.stop()
        session.offRouteDetector.reset()
        locationService.configureForStandard()

        activeSessionPublisher.send(nil)
        navigationCommandPublisher.send(.stopped)
    }
}
