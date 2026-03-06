import CoreLocation

final class KakaoGeocodingService: GeocodingProviding {

    func reverseGeocode(location: CLLocation) async throws -> Place {
        let queryItems = [
            URLQueryItem(name: "x", value: "\(location.coordinate.longitude)"),
            URLQueryItem(name: "y", value: "\(location.coordinate.latitude)"),
        ]

        let response: KakaoGeocodingResponse = try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/geo/coord2address.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )

        guard let doc = response.documents.first else {
            throw LBSError.noResults
        }

        return Place(
            name: nil,
            coordinate: location.coordinate,
            address: doc.roadAddress?.addressName ?? doc.address?.addressName,
            providerRawData: doc
        )
    }

    func geocode(address: String) async throws -> Place {
        let queryItems = [
            URLQueryItem(name: "query", value: address),
        ]

        let response: KakaoSearchResponse = try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/search/address.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )

        guard let doc = response.documents.first,
              let lat = Double(doc.y),
              let lng = Double(doc.x) else {
            throw LBSError.noResults
        }

        return Place(
            name: doc.placeName,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            address: doc.addressName,
            providerRawData: doc
        )
    }
}
