import CoreLocation

/// 지도 기하 계산 유틸리티
enum MapGeometry {

    /// 두 좌표 간 방위각 (0~360, 0=북 시계방향)
    static func bearing(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 폴리라인 첫 segment 의 방위각. 좌표가 1개 이하면 nil.
    static func firstBearing(of polyline: [CLLocationCoordinate2D]) -> CLLocationDirection? {
        guard polyline.count >= 2 else { return nil }
        return bearing(from: polyline[0], to: polyline[1])
    }

    /// 두 방위각의 최소 부호 차이 (-180...+180)
    static func angleDelta(_ a: CLLocationDirection, _ b: CLLocationDirection) -> Double {
        let d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { return d - 360 }
        if d < -180 { return d + 360 }
        return d
    }
}
