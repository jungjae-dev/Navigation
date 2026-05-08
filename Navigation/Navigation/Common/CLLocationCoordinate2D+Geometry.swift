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

    /// bearing 방향으로 distance(m) 이동한 좌표 (haversine 역산)
    func moved(distance: CLLocationDistance, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6_371_000
        let bearingRad = bearing * .pi / 180
        let lat1 = latitude  * .pi / 180
        let lon1 = longitude * .pi / 180
        let angDist = distance / earthRadius

        let lat2 = asin(sin(lat1) * cos(angDist)
                      + cos(lat1) * sin(angDist) * cos(bearingRad))
        let lon2 = lon1 + atan2(
            sin(bearingRad) * sin(angDist) * cos(lat1),
            cos(angDist) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(
            latitude:  lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
}
