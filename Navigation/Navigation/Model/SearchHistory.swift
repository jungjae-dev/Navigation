import SwiftData
import CoreLocation

@Model
final class SearchHistory {
    var id: UUID
    var query: String
    var placeName: String
    var address: String
    var latitude: Double
    var longitude: Double
    var searchedAt: Date

    init(
        query: String,
        placeName: String,
        address: String,
        latitude: Double,
        longitude: Double
    ) {
        self.id = UUID()
        self.query = query
        self.placeName = placeName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.searchedAt = Date()
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
