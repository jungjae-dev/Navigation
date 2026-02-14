import SwiftData
import CoreLocation

@Model
final class FavoritePlace {
    var id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var sortOrder: Int
    var createdAt: Date
    var lastUsedAt: Date

    init(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        category: String = "custom"
    ) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.sortOrder = 0
        self.createdAt = Date()
        self.lastUsedAt = Date()
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
