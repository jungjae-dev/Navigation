import Foundation

/// 회전 유형
enum TurnType: Sendable, Equatable {
    case straight
    case leftTurn
    case rightTurn
    case uTurn
    case leftMerge
    case rightMerge
    case leftExit
    case rightExit
    case destination
    case unknown(String)    // 매핑 안 되는 경우 instruction 텍스트 저장

    /// SF Symbol 아이콘 이름
    var iconName: String {
        switch self {
        case .straight:     return "arrow.up"
        case .leftTurn:     return "arrow.turn.up.left"
        case .rightTurn:    return "arrow.turn.up.right"
        case .uTurn:        return "arrow.uturn.left"
        case .leftMerge:    return "arrow.merge"
        case .rightMerge:   return "arrow.merge"
        case .leftExit:     return "arrow.turn.up.left"
        case .rightExit:    return "arrow.turn.up.right"
        case .destination:  return "mappin.circle.fill"
        case .unknown:      return "arrow.up"
        }
    }

    /// 카카오 guide.type 코드에서 TurnType 변환
    static func from(kakaoType: Int) -> TurnType {
        switch kakaoType {
        case 11:        return .straight
        case 12:        return .leftTurn
        case 13:        return .rightTurn
        case 14:        return .uTurn
        case 15:        return .leftTurn         // P턴 (좌회전 유사)
        case 16:        return .uTurn            // U턴
        case 17:        return .leftMerge
        case 18:        return .rightMerge
        case 19:        return .leftMerge        // 8시 방향 (좌측 합류 유사)
        case 20:        return .rightExit        // 10시 방향
        case 21:        return .leftExit         // 2시 방향
        case 22:        return .rightMerge       // 4시 방향 (우측 합류 유사)
        // 고속도로 진입/출구
        case 100...106: return .straight         // 고속도로 직진
        case 107:       return .rightExit        // 오른쪽 출구
        case 108:       return .leftExit         // 왼쪽 출구
        case 111...118: return .straight         // 도시고속
        // 시설
        case 200:       return .straight         // 출발지
        case 201:       return .destination       // 목적지
        case 185...189: return .destination       // 경유지
        default:        return .unknown("kakao_type_\(kakaoType)")
        }
    }

    /// Apple instructions 텍스트에서 TurnType 추론 (한국어 기기 기준)
    /// Step 1에서 실제 API 데이터를 캡처한 후 패턴 보강 예정
    static func from(appleInstructions: String) -> TurnType {
        let text = appleInstructions.lowercased()

        // 한국어 키워드
        if text.contains("우회전") || text.contains("오른쪽") { return .rightTurn }
        if text.contains("좌회전") || text.contains("왼쪽") { return .leftTurn }
        if text.contains("유턴") || text.contains("u턴") { return .uTurn }
        if text.contains("합류") || text.contains("진입") { return .rightMerge }
        if text.contains("출구") { return .rightExit }
        if text.contains("도착") || text.contains("목적지") { return .destination }
        if text.contains("직진") { return .straight }

        // 영어 키워드 (영어 기기 fallback)
        if text.contains("turn right") || text.contains("right turn") { return .rightTurn }
        if text.contains("turn left") || text.contains("left turn") { return .leftTurn }
        if text.contains("u-turn") || text.contains("u turn") { return .uTurn }
        if text.contains("merge") { return .rightMerge }
        if text.contains("exit") { return .rightExit }
        if text.contains("arrive") || text.contains("destination") { return .destination }
        if text.contains("straight") || text.contains("continue") { return .straight }

        return .unknown(appleInstructions)
    }
}
