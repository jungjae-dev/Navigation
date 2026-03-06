import MapKit

final class SearchResultAnnotation: NSObject, MKAnnotation {

    let place: Place
    var isFocused: Bool = false

    @objc dynamic var coordinate: CLLocationCoordinate2D

    var title: String? {
        place.name
    }

    var subtitle: String? {
        place.address
    }

    init(place: Place) {
        self.place = place
        self.coordinate = place.coordinate
        super.init()
    }
}
