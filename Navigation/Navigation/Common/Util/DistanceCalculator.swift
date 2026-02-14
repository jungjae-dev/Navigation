import CoreLocation
import MapKit

enum DistanceCalculator {

    // MARK: - Point to Point

    /// Distance between two coordinates in meters (Haversine formula)
    static func distance(
        from coord1: CLLocationCoordinate2D,
        to coord2: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }

    // MARK: - Point to Segment

    /// Shortest distance from a point to a line segment defined by two endpoints (meters)
    static func distanceFromPoint(
        _ point: CLLocationCoordinate2D,
        toSegmentStart segStart: CLLocationCoordinate2D,
        segmentEnd segEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        // Convert to flat 2D for projection (use meters relative to segStart)
        let px = longitudeToMeters(point.longitude - segStart.longitude, atLatitude: segStart.latitude)
        let py = latitudeToMeters(point.latitude - segStart.latitude)

        let sx = 0.0
        let sy = 0.0

        let ex = longitudeToMeters(segEnd.longitude - segStart.longitude, atLatitude: segStart.latitude)
        let ey = latitudeToMeters(segEnd.latitude - segStart.latitude)

        let dx = ex - sx
        let dy = ey - sy
        let lengthSquared = dx * dx + dy * dy

        // If segment is a point, return distance to that point
        if lengthSquared < 1e-10 {
            return distance(from: point, to: segStart)
        }

        // Project point onto segment, clamped to [0, 1]
        let t = max(0, min(1, ((px - sx) * dx + (py - sy) * dy) / lengthSquared))

        // Nearest point on segment
        let nearestX = sx + t * dx
        let nearestY = sy + t * dy

        let distX = px - nearestX
        let distY = py - nearestY

        return sqrt(distX * distX + distY * distY)
    }

    // MARK: - Polyline Search

    /// Find nearest point on a polyline within an optional search range
    /// Returns (distance in meters, segment index of nearest point)
    static func nearestPointOnPolyline(
        _ polyline: MKPolyline,
        from point: CLLocationCoordinate2D,
        searchRange: ClosedRange<Int>? = nil
    ) -> (distance: CLLocationDistance, segmentIndex: Int) {
        let pointCount = polyline.pointCount
        guard pointCount >= 2 else {
            return (CLLocationDistanceMax, 0)
        }

        let coordinates = polyline.coordinates

        let startIndex: Int
        let endIndex: Int

        if let range = searchRange {
            startIndex = max(0, range.lowerBound)
            endIndex = min(pointCount - 2, range.upperBound)
        } else {
            startIndex = 0
            endIndex = pointCount - 2
        }

        guard startIndex <= endIndex else {
            return (CLLocationDistanceMax, 0)
        }

        var minDistance: CLLocationDistance = CLLocationDistanceMax
        var nearestSegment = startIndex

        for i in startIndex...endIndex {
            let segStart = coordinates[i]
            let segEnd = coordinates[i + 1]

            let dist = distanceFromPoint(point, toSegmentStart: segStart, segmentEnd: segEnd)
            if dist < minDistance {
                minDistance = dist
                nearestSegment = i
            }
        }

        return (minDistance, nearestSegment)
    }

    // MARK: - Helpers

    private static func latitudeToMeters(_ degreesLatitude: Double) -> Double {
        degreesLatitude * 111_320.0
    }

    private static func longitudeToMeters(_ degreesLongitude: Double, atLatitude latitude: Double) -> Double {
        degreesLongitude * 111_320.0 * cos(latitude * .pi / 180.0)
    }
}

// MARK: - MKPolyline Extension

extension MKPolyline {

    /// Extract all coordinates from the polyline
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
