import Foundation
import MapKit
import CoreLocation

/// 앱 내부 user location annotation (시스템 MKUserLocation 대체)
final class UserLocationAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var heading: CLLocationDirection

    init(
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(),
        heading: CLLocationDirection = 0
    ) {
        self.coordinate = coordinate
        self.heading = heading
    }
}
