import CoreLocation

/// 엔진 출력 — 1초마다 발행되는 단일 구조체
/// iPhone UI, CarPlay, VoiceTTS가 이 구조체를 구독하여 화면/음성 갱신
struct NavigationGuide: Sendable {
    // 상태
    let state: NavigationState

    // 현재 안내
    let currentManeuver: ManeuverInfo?
    let nextManeuver: ManeuverInfo?

    // 진행 정보
    let remainingDistance: CLLocationDistance
    let remainingTime: TimeInterval
    let eta: Date

    // 위치
    let matchedPosition: CLLocationCoordinate2D
    let heading: CLLocationDirection
    let speed: CLLocationSpeed

    // GPS 상태
    let isGPSValid: Bool

    // 음성
    let voiceCommand: VoiceCommand?
}
