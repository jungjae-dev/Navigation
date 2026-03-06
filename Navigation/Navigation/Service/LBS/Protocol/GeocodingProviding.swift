import CoreLocation

protocol GeocodingProviding: AnyObject {

    func reverseGeocode(location: CLLocation) async throws -> Place
    func geocode(address: String) async throws -> Place
}
