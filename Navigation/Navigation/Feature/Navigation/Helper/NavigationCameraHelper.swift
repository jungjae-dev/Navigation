import MapKit

/// 주행 카메라 설정 (속도별 고도/피치)
enum NavigationCameraHelper {

    /// 속도 기반 카메라 고도 계산 (TMAP 값)
    static func altitude(for speed: CLLocationSpeed, mode: TransportMode) -> CLLocationDistance {
        let kmh = speed * 3.6

        switch mode {
        case .automobile:
            if kmh < 10 { return 500 }
            if kmh < 80 { return 500 + (kmh - 10) / 70 * 500 }    // 500~1000
            return 1000 + (min(kmh, 120) - 80) / 40 * 1000         // 1000~2000

        case .walking:
            if kmh < 2 { return 200 }
            return 200 + (min(kmh, 10) - 2) / 8 * 100              // 200~300
        }
    }

    /// 교통 모드별 피치
    static func pitch(for mode: TransportMode) -> CGFloat {
        switch mode {
        case .automobile: return 45
        case .walking: return 30
        }
    }

    /// 주행 카메라 생성
    static func makeCamera(
        center: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        speed: CLLocationSpeed,
        mode: TransportMode
    ) -> MKMapCamera {
        let camera = MKMapCamera()
        camera.centerCoordinate = center
        camera.heading = heading
        camera.centerCoordinateDistance = altitude(for: speed, mode: mode)
        camera.pitch = pitch(for: mode)
        return camera
    }
}
