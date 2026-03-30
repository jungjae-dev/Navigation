import CoreLocation

/// 맵매칭 결과 (엔진 내부)
struct MatchResult: Sendable {
    let isMatched: Bool
    let coordinate: CLLocationCoordinate2D    // 매칭된 좌표 (실패 시 원본 GPS 좌표)
    let segmentIndex: Int                     // 폴리라인 세그먼트 인덱스
    let distanceFromRoute: CLLocationDistance  // 경로로부터 거리
    let headingDelta: CLLocationDirection     // GPS heading과 세그먼트 방향 차이
}
