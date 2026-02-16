import Testing
import CoreLocation
import MapKit
@testable import Navigation

struct DistanceCalculatorTests {

    // MARK: - Test Coordinates

    // Seoul City Hall
    private let seoulCityHall = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    // Gangnam Station
    private let gangnamStation = CLLocationCoordinate2D(latitude: 37.4979, longitude: 127.0276)
    // Gwanghwamun
    private let gwanghwamun = CLLocationCoordinate2D(latitude: 37.5760, longitude: 126.9769)

    // MARK: - distance(from:to:)

    @Test func distanceBetweenSamPoint() {
        let dist = DistanceCalculator.distance(from: seoulCityHall, to: seoulCityHall)
        #expect(dist < 1.0)
    }

    @Test func distanceSeoulToGangnam() {
        let dist = DistanceCalculator.distance(from: seoulCityHall, to: gangnamStation)
        // ~8.5km ± 1km
        #expect(dist > 7_500 && dist < 9_500)
    }

    @Test func distanceIsSymmetric() {
        let d1 = DistanceCalculator.distance(from: seoulCityHall, to: gangnamStation)
        let d2 = DistanceCalculator.distance(from: gangnamStation, to: seoulCityHall)
        #expect(abs(d1 - d2) < 1.0) // Within 1 meter tolerance
    }

    // MARK: - distanceFromPoint(toSegmentStart:segmentEnd:)

    @Test func pointOnSegmentReturnsZero() {
        // Point is exactly on the segment (midpoint)
        let mid = CLLocationCoordinate2D(
            latitude: (seoulCityHall.latitude + gangnamStation.latitude) / 2,
            longitude: (seoulCityHall.longitude + gangnamStation.longitude) / 2
        )
        let dist = DistanceCalculator.distanceFromPoint(
            mid,
            toSegmentStart: seoulCityHall,
            segmentEnd: gangnamStation
        )
        // Should be close to 0 (small error due to flat projection)
        #expect(dist < 100.0)
    }

    @Test func pointFarFromSegment() {
        // Gwanghwamun is north of City Hall
        // Segment from City Hall going south to Gangnam
        let dist = DistanceCalculator.distanceFromPoint(
            gwanghwamun,
            toSegmentStart: seoulCityHall,
            segmentEnd: gangnamStation
        )
        // Should be roughly the distance from Gwanghwamun to City Hall (~1km)
        #expect(dist > 500 && dist < 2_000)
    }

    @Test func degenerateSegmentReturnsPointDistance() {
        // Segment is a single point
        let dist = DistanceCalculator.distanceFromPoint(
            gangnamStation,
            toSegmentStart: seoulCityHall,
            segmentEnd: seoulCityHall
        )
        let expected = DistanceCalculator.distance(from: gangnamStation, to: seoulCityHall)
        #expect(abs(dist - expected) < 100.0)
    }

    // MARK: - nearestPointOnPolyline

    @Test func nearestPointOnSimplePolyline() {
        let coords: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97),
            CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
            CLLocationCoordinate2D(latitude: 37.54, longitude: 126.99),
            CLLocationCoordinate2D(latitude: 37.53, longitude: 127.00),
        ]

        let polyline = MKPolyline(coordinates: coords, count: coords.count)

        // Point near the second segment
        let testPoint = CLLocationCoordinate2D(latitude: 37.545, longitude: 126.985)
        let result = DistanceCalculator.nearestPointOnPolyline(polyline, from: testPoint)

        #expect(result.segmentIndex == 1 || result.segmentIndex == 2)
        #expect(result.distance < 1_000) // Within 1km
    }

    @Test func nearestPointOnPolylineWithRange() {
        let coords: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97),
            CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
            CLLocationCoordinate2D(latitude: 37.54, longitude: 126.99),
            CLLocationCoordinate2D(latitude: 37.53, longitude: 127.00),
        ]

        let polyline = MKPolyline(coordinates: coords, count: coords.count)

        // Point near the first segment, but restrict search to last segment
        let testPoint = CLLocationCoordinate2D(latitude: 37.555, longitude: 126.975)
        let result = DistanceCalculator.nearestPointOnPolyline(
            polyline,
            from: testPoint,
            searchRange: 2...2
        )

        // Forced to segment 2 even though segment 0 would be closer
        #expect(result.segmentIndex == 2)
    }

    @Test func singlePointPolyline() {
        let coord = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        let polyline = MKPolyline(coordinates: [coord], count: 1)

        let result = DistanceCalculator.nearestPointOnPolyline(polyline, from: gangnamStation)
        #expect(result.distance == CLLocationDistanceMax)
    }

    // MARK: - MKPolyline.coordinates extension

    @Test func polylineCoordinatesExtraction() {
        let coords: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97),
            CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
            CLLocationCoordinate2D(latitude: 37.54, longitude: 126.99),
        ]

        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        let extracted = polyline.coordinates

        #expect(extracted.count == 3)
        #expect(abs(extracted[0].latitude - 37.56) < 0.001)
        #expect(abs(extracted[1].longitude - 126.98) < 0.001)
        #expect(abs(extracted[2].latitude - 37.54) < 0.001)
    }
}
