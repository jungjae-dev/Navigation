import Foundation

/// 네비게이션 주행 상태
enum NavigationState: Sendable, Equatable {
    case preparing      // 엔진 초기화, 첫 GPS 대기
    case navigating     // 정상 주행 중
    case rerouting      // 경로 재탐색 중
    case arrived        // 목적지 도착 (30m 이내)
    case stopped        // 사용자 종료
}
