import CoreLocation

extension CLLocation {

    /// 앱 합성 GPS 손실 신호 sentinel 값 (1.1s 무응답 시 RealGPSProvider가 발행)
    static let gpsLossAccuracy: CLLocationAccuracy = 500

    /// handleTickTimeout()이 생성한 합성 GPS 손실 신호 여부
    var isGPSLoss: Bool {
        horizontalAccuracy == Self.gpsLossAccuracy
    }

    /// 실제 iPhone GPS 유효 여부 (합성 신호 제외)
    var isValid: Bool {
        horizontalAccuracy >= 0 && !isGPSLoss
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
