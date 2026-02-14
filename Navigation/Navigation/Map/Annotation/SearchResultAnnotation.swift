import MapKit

final class SearchResultAnnotation: NSObject, MKAnnotation {

    let mapItem: MKMapItem
    var isFocused: Bool = false

    @objc dynamic var coordinate: CLLocationCoordinate2D

    var title: String? {
        mapItem.name
    }

    var subtitle: String? {
        mapItem.placemark.title
    }

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
        self.coordinate = mapItem.placemark.coordinate
        super.init()
    }
}
