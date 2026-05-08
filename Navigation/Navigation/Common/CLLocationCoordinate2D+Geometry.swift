import CoreLocation

extension CLLocationCoordinate2D {

    /// 두 좌표 간 거리 (미터)
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// 두 좌표 사이를 t (0~1) 비율로 선형 보간한 좌표
    func interpolated(to other: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:  latitude  + (other.latitude  - latitude)  * t,
            longitude: longitude + (other.longitude - longitude) * t
        )
    }
}
