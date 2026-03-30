import CoreLocation

/// Dead Reckoning 추정 결과 (GPS 손실 시)
struct DeadReckoningResult: Sendable {
    let coordinate: CLLocationCoordinate2D    // 추정 좌표
    let heading: CLLocationDirection          // 폴리라인 세그먼트 방향
    let segmentIndex: Int                     // 전진한 세그먼트 위치
}
