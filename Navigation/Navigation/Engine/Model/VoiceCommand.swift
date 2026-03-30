import Foundation

/// 음성 안내 명령 (엔진이 생성, Presentation에서 TTS 재생)
struct VoiceCommand: Sendable {
    let text: String                          // TTS에 전달할 텍스트
    let priority: VoicePriority
}

/// 음성 우선순위
enum VoicePriority: Sendable {
    case normal                               // 일반 안내
    case urgent                               // 재탐색, 도착 등
}
