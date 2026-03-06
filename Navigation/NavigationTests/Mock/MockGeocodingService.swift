import CoreLocation
@testable import Navigation

final class MockGeocodingService: GeocodingProviding {

    var mockPlace: Place = TestFixtures.samplePlace
    var shouldThrow: LBSError?

    func reverseGeocode(location: CLLocation) async throws -> Place {
        if let error = shouldThrow { throw error }
        return mockPlace
    }

    func geocode(address: String) async throws -> Place {
        if let error = shouldThrow { throw error }
        return mockPlace
    }
}
