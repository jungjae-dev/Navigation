import MapKit
import CoreLocation

final class AppleGeocodingService: GeocodingProviding {

    // MARK: - GeocodingProviding

    func reverseGeocode(location: CLLocation) async throws -> Place {
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
            throw LBSError.noResults
        }
        return AppleModelConverter.place(from: item)
    }

    func geocode(address: String) async throws -> Place {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        guard let item = response.mapItems.first else {
            throw LBSError.noResults
        }
        return AppleModelConverter.place(from: item)
    }
}
