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

    /// 맵매칭 전 원본 GPS 좌표 (디버그/시각화 용도). GPS valid 시에만 set, 그 외 nil.
    let rawGPSPosition: CLLocationCoordinate2D?
    /// 원본 GPS heading. rawGPSPosition 와 짝.
    let rawGPSHeading: CLLocationDirection?
    /// 매칭 성공 여부 (실제 도로 위에 있으면 true). 디버그 표시 색상 분기 등에 사용.
    let isMatched: Bool

    // GPS 상태
    let isGPSValid: Bool

    // 음성
    let voiceCommand: VoiceCommand?
}
