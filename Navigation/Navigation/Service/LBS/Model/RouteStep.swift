import CoreLocation

struct RouteStep: Sendable {
    let instructions: String
    let distance: CLLocationDistance
    let polylineCoordinates: [CLLocationCoordinate2D]
    let duration: TimeInterval?               // 구간 예상 시간 (카카오만 제공)
    let turnType: TurnType                    // 회전 유형
    let roadName: String?                     // 도로명 (카카오만 제공)
}

