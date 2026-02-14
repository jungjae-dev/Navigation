import MapKit

final class VehicleAnnotation: NSObject, MKAnnotation {

    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }

    func updatePosition(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}
