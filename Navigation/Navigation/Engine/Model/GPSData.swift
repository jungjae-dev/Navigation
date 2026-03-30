import CoreLocation

/// 엔진에 전달되는 GPS 데이터 (1초마다 GPSProvider에서 발행)
struct GPSData: Sendable {
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection          // 0~360
    let speed: CLLocationSpeed                // m/s
    let accuracy: CLLocationAccuracy          // meters
    let timestamp: Date
    let isValid: Bool                         // GPS 수신 여부
}
