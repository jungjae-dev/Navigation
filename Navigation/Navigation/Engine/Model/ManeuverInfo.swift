import CoreLocation

/// 회전 안내 정보 (current/next 공용)
struct ManeuverInfo: Sendable {
    let instruction: String                   // "우회전하세요"
    let distance: CLLocationDistance           // 안내 포인트까지 남은 거리
    let turnType: TurnType                    // 회전 유형
    let roadName: String?                     // "테헤란로" (있으면)
}
