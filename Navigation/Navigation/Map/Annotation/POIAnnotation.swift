import MapKit

final class POIAnnotation: NSObject, MKAnnotation {

    let place: Place

    @objc dynamic var coordinate: CLLocationCoordinate2D

    var title: String? {
        place.name
    }

    var subtitle: String? {
        place.address
    }

    var glyphIconName: String {
        POICategoryIcon.iconName(for: place.category)
    }

    init(place: Place) {
        self.place = place
        self.coordinate = place.coordinate
        super.init()
    }
}
