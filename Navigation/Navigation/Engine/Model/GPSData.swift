import CoreLocation

/// 엔진에 전달되는 GPS 데이터 (GPSProvider에서 발행)
struct GPSData: Sendable {
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection          // 0~360
    let speed: CLLocationSpeed                // m/s
    let accuracy: CLLocationAccuracy          // meters
    let timestamp: Date
    let isValid: Bool                         // GPS 수신 여부

    /// 주행 맵매칭에 사용 가능한 accuracy 여부 (0~100m)
    var isAccurateForNavigation: Bool {
        accuracy >= 0 && accuracy <= CLLocation.navigationAccuracyThreshold
    }
}
