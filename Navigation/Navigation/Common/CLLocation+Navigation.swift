import CoreLocation

extension CLLocation {

    /// 주행 맵매칭 accuracy 임계값 (100m)
    static let navigationAccuracyThreshold: CLLocationAccuracy = 100

    /// 기본화면 표시용 — 유효한 좌표 (accuracy >= 0)
    var isValidForDisplay: Bool {
        horizontalAccuracy >= 0
    }

    /// 주행 맵매칭용 — accuracy 100m 이내
    var isValidForNavigation: Bool {
        horizontalAccuracy >= 0 && horizontalAccuracy <= Self.navigationAccuracyThreshold
    }

    /// GPS course 유효 여부
    var hasValidCourse: Bool {
        course >= 0
    }

    /// speed < 0 (미확인) 을 0으로 클램핑 — CLLocation.speed = -1 은 "알 수 없음" 의미
    var safeSpeed: CLLocationSpeed {
        max(0, speed)
    }
}
