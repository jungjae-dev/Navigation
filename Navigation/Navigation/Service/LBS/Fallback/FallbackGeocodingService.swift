import CoreLocation

final class FallbackGeocodingService: GeocodingProviding {

    private let primary: GeocodingProviding
    private let fallback: GeocodingProviding

    init(primary: GeocodingProviding, fallback: GeocodingProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    func reverseGeocode(location: CLLocation) async throws -> Place {
        do {
            return try await primary.reverseGeocode(location: location)
        } catch let error as LBSError where error == .quotaExceeded {
            return try await fallback.reverseGeocode(location: location)
        }
    }

    func geocode(address: String) async throws -> Place {
        do {
            return try await primary.geocode(address: address)
        } catch let error as LBSError where error == .quotaExceeded {
            return try await fallback.geocode(address: address)
        }
    }
}
