import Foundation
import Combine
import MapKit
import CoreLocation

final class OffRouteDetector {

    // MARK: - Publishers

    let isOffRoutePublisher = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Configuration

    private let offRouteThreshold: CLLocationDistance = 50.0
    private let requiredConfirmations = 3

    // MARK: - State

    private var consecutiveOffRouteCount = 0
    private var currentSegmentIndex = 0
    private var routePolyline: MKPolyline?

    // MARK: - Public

    func configure(with route: MKRoute) {
        routePolyline = route.polyline
        reset()
    }

    /// Check if location is off-route. Returns true if off-route is confirmed (3 consecutive checks).
    func checkLocation(_ location: CLLocation) -> Bool {
        guard let polyline = routePolyline else { return false }

        let result = calculateDistanceToRoute(
            from: location.coordinate,
            polyline: polyline
        )

        if result.distance > offRouteThreshold {
            consecutiveOffRouteCount += 1

            if consecutiveOffRouteCount >= requiredConfirmations {
                isOffRoutePublisher.send(true)
                return true
            }
        } else {
            // On route — update segment index and reset counter
            consecutiveOffRouteCount = 0
            currentSegmentIndex = result.nearestSegment
            isOffRoutePublisher.send(false)
        }

        return false
    }

    func reset() {
        consecutiveOffRouteCount = 0
        currentSegmentIndex = 0
        isOffRoutePublisher.send(false)
    }

    // MARK: - Private

    private func calculateDistanceToRoute(
        from coordinate: CLLocationCoordinate2D,
        polyline: MKPolyline
    ) -> (distance: CLLocationDistance, nearestSegment: Int) {
        // Search only in a window around the current segment for performance
        let windowSize = 5
        let lowerBound = max(0, currentSegmentIndex - windowSize)
        let upperBound = min(polyline.pointCount - 2, currentSegmentIndex + windowSize)

        let searchRange = lowerBound...upperBound

        let result = DistanceCalculator.nearestPointOnPolyline(
            polyline,
            from: coordinate,
            searchRange: searchRange
        )
        return (distance: result.distance, nearestSegment: result.segmentIndex)
    }
}
