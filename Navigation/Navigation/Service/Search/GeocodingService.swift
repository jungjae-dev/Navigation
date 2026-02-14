import MapKit
import CoreLocation

final class GeocodingService {

    // MARK: - Public Methods

    func reverseGeocode(location: CLLocation) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = nil
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 100,
            longitudinalMeters: 100
        )

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        guard let item = response.mapItems.first else {
            throw GeocodingError.noResults
        }
        return item
    }

    func geocode(address: String) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        guard let item = response.mapItems.first else {
            throw GeocodingError.noResults
        }
        return item
    }
}

// MARK: - Error

enum GeocodingError: Error, LocalizedError {
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "주소를 찾을 수 없습니다"
        }
    }
}
