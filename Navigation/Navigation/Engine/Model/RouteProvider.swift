import Foundation

/// 경로 제공자 (음성 텍스트 생성 분기에 사용)
enum RouteProvider: String, Sendable {
    case kakao
    case apple
}
