import Testing
import Combine
import CoreLocation
import MapKit
@testable import Navigation

struct OffRouteDetectorTests {

    // MARK: - Helpers

    private func makePolyline() -> MKPolyline {
        // Straight line from (37.56, 126.97) → (37.54, 126.99)
        let coords: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97),
            CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
            CLLocationCoordinate2D(latitude: 37.54, longitude: 126.99),
        ]
        return MKPolyline(coordinates: coords, count: coords.count)
    }

    private func makeRoute() -> MKRoute {
        // We can't easily create MKRoute, so test via polyline directly
        // Using OffRouteDetector's configure() which extracts polyline from MKRoute
        // For unit testing, we test checkLocation via a configured route
        // We'll use a stub approach
        return StubRoute(polyline: makePolyline())
    }

    private func makeDetector() -> OffRouteDetector {
        let detector = OffRouteDetector()
        return detector
    }

    // MARK: - Tests

    @Test func onRouteLocationReturnsFalse() {
        let detector = makeDetector()
        // Manually set polyline via configure
        let route = makeRoute()
        detector.configure(with: route)

        // Point on the route
        let onRouteLocation = CLLocation(latitude: 37.55, longitude: 126.98)
        let result = detector.checkLocation(onRouteLocation)

        #expect(!result)
        #expect(!detector.isOffRoutePublisher.value)
    }

    @Test func singleOffRouteCheckDoesNotConfirm() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        // Point far from route (e.g., 500m away)
        let offRouteLocation = CLLocation(latitude: 37.56, longitude: 127.01)
        let result = detector.checkLocation(offRouteLocation)

        #expect(!result) // Not confirmed yet (needs 3)
    }

    @Test func threeConsecutiveOffRouteConfirms() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        let offRouteLocation = CLLocation(latitude: 37.56, longitude: 127.01)

        _ = detector.checkLocation(offRouteLocation) // 1
        _ = detector.checkLocation(offRouteLocation) // 2
        let result = detector.checkLocation(offRouteLocation) // 3

        #expect(result)
        #expect(detector.isOffRoutePublisher.value)
    }

    @Test func onRouteResetsCounter() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        let offRouteLocation = CLLocation(latitude: 37.56, longitude: 127.01)
        let onRouteLocation = CLLocation(latitude: 37.55, longitude: 126.98)

        _ = detector.checkLocation(offRouteLocation) // 1
        _ = detector.checkLocation(offRouteLocation) // 2
        _ = detector.checkLocation(onRouteLocation) // Reset

        let result = detector.checkLocation(offRouteLocation) // 1 again
        #expect(!result) // Still not confirmed
    }

    @Test func resetClearsState() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        let offRouteLocation = CLLocation(latitude: 37.56, longitude: 127.01)

        _ = detector.checkLocation(offRouteLocation)
        _ = detector.checkLocation(offRouteLocation)

        detector.reset()

        #expect(!detector.isOffRoutePublisher.value)

        // After reset, need 3 more
        _ = detector.checkLocation(offRouteLocation)
        let result = detector.checkLocation(offRouteLocation)
        #expect(!result)
    }

    @Test func noPolylineAlwaysReturnsFalse() {
        let detector = makeDetector()
        // No configure called

        let location = CLLocation(latitude: 37.56, longitude: 127.01)
        let result = detector.checkLocation(location)
        #expect(!result)
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
