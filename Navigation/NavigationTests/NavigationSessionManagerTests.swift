import Testing
import Combine
import MapKit
import CoreLocation
@testable import Navigation

struct NavigationSessionManagerTests {

    // MARK: - Helpers

    private var sessionManager: NavigationSessionManager {
        NavigationSessionManager.shared
    }

    private func makeRoute() -> MKRoute {
        // Use a stub route for testing
        let coords: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97),
            CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
        ]
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        return StubRoute(polyline: polyline)
    }

    private func makeDestination() -> MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: 37.55, longitude: 126.98),
            address: nil
        )
    }

    // MARK: - Tests

    @Test func initialStateIsNotNavigating() {
        // Ensure stopped before test
        sessionManager.stopNavigation()

        #expect(!sessionManager.isNavigating)
        #expect(sessionManager.activeSessionPublisher.value == nil)
    }

    @Test func startNavigationCreatesSession() {
        let route = makeRoute()
        let destination = makeDestination()

        sessionManager.startNavigation(
            route: route,
            destination: destination,
            source: .phone
        )

        #expect(sessionManager.isNavigating)
        #expect(sessionManager.activeSessionPublisher.value != nil)

        // Cleanup
        sessionManager.stopNavigation()
    }

    @Test func stopNavigationClearsSession() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .phone
        )

        sessionManager.stopNavigation()

        #expect(!sessionManager.isNavigating)
        #expect(sessionManager.activeSessionPublisher.value == nil)
    }

    @Test func commandPublisherEmitsStarted() {
        var receivedCommand: NavigationCommand?
        var cancellables = Set<AnyCancellable>()

        sessionManager.navigationCommandPublisher
            .sink { command in
                receivedCommand = command
            }
            .store(in: &cancellables)

        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .carPlay
        )

        if case .started(let source) = receivedCommand {
            #expect(source == .carPlay)
        } else {
            Issue.record("Expected .started command")
        }

        sessionManager.stopNavigation()
        cancellables.removeAll()
    }

    @Test func commandPublisherEmitsStopped() {
        var receivedCommand: NavigationCommand?
        var cancellables = Set<AnyCancellable>()

        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .phone
        )

        sessionManager.navigationCommandPublisher
            .sink { command in
                receivedCommand = command
            }
            .store(in: &cancellables)

        sessionManager.stopNavigation()

        if case .stopped = receivedCommand {
            // OK
        } else {
            Issue.record("Expected .stopped command")
        }

        cancellables.removeAll()
    }

    @Test func startingWhileNavigatingStopsPrevious() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .phone
        )

        let firstSession = sessionManager.activeSessionPublisher.value

        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .carPlay
        )

        let secondSession = sessionManager.activeSessionPublisher.value

        // Should be a different session (new GuidanceEngine)
        #expect(firstSession?.guidanceEngine !== secondSession?.guidanceEngine)

        sessionManager.stopNavigation()
    }

    @Test func stopWhenNotNavigatingIsNoOp() {
        sessionManager.stopNavigation() // already stopped
        sessionManager.stopNavigation() // should not crash
        #expect(!sessionManager.isNavigating)
    }
}

// MARK: - Stub MKRoute

private final class StubRoute: MKRoute {
    private let _polyline: MKPolyline

    init(polyline: MKPolyline) {
        self._polyline = polyline
        super.init()
    }

    override var polyline: MKPolyline {
        _polyline
    }
}
