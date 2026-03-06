import Testing
import Combine
import CoreLocation
@testable import Navigation

struct OffRouteDetectorTests {

    // MARK: - Helpers

    private func makeRoute() -> Route {
        Route(
            id: "test",
            distance: 3000,
            expectedTravelTime: 300,
            name: "테스트",
            steps: [],
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97),
                CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
                CLLocationCoordinate2D(latitude: 37.54, longitude: 126.99),
            ],
            transportMode: .automobile
        )
    }

    private func makeDetector() -> OffRouteDetector {
        OffRouteDetector()
    }

    // MARK: - Tests

    @Test func onRouteLocationReturnsFalse() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        let onRouteLocation = CLLocation(latitude: 37.55, longitude: 126.98)
        let result = detector.checkLocation(onRouteLocation)

        #expect(!result)
        #expect(!detector.isOffRoutePublisher.value)
    }

    @Test func singleOffRouteCheckDoesNotConfirm() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        let offRouteLocation = CLLocation(latitude: 37.56, longitude: 127.01)
        let result = detector.checkLocation(offRouteLocation)

        #expect(!result)
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
        #expect(!result)
    }

    @Test func resetClearsState() {
        let detector = makeDetector()
        detector.configure(with: makeRoute())

        let offRouteLocation = CLLocation(latitude: 37.56, longitude: 127.01)

        _ = detector.checkLocation(offRouteLocation)
        _ = detector.checkLocation(offRouteLocation)

        detector.reset()

        #expect(!detector.isOffRoutePublisher.value)

        _ = detector.checkLocation(offRouteLocation)
        let result = detector.checkLocation(offRouteLocation)
        #expect(!result)
    }

    @Test func noPolylineAlwaysReturnsFalse() {
        let detector = makeDetector()

        let location = CLLocation(latitude: 37.56, longitude: 127.01)
        let result = detector.checkLocation(location)
        #expect(!result)
    }
}
