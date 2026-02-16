import MapKit

final class VehicleAnnotation: NSObject, MKAnnotation {

    @objc dynamic var coordinate: CLLocationCoordinate2D

    /// Vehicle heading in degrees (0 = north, 90 = east)
    var heading: CLLocationDirection = 0

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }

    func updatePosition(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }

    func updatePosition(_ coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        self.coordinate = coordinate
        self.heading = heading
    }
}
