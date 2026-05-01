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

    /// 카카오 모빌리티 API guide.type 코드에서 TurnType 변환
    /// 참고: https://developers.kakaomobility.com/docs/navi-api/directions/
    static func from(kakaoType: Int) -> TurnType {
        switch kakaoType {
        // 기본 회전
        case 0:         return .straight         // 출발지 / 직진
        case 1:         return .leftTurn         // 좌회전
        case 2:         return .rightTurn        // 우회전
        case 3:         return .uTurn            // U턴
        // 방향
        case 5:         return .leftTurn         // 왼쪽 방향 (슬라이트 좌회전)
        case 6:         return .rightTurn        // 오른쪽 방향 (슬라이트 우회전)
        // 고속도로/도시고속
        case 7:         return .straight         // 고속도로 진입
        case 8:         return .rightExit        // 고속도로 출구
        // 특수 시설
        case 9:         return .leftTurn         // 왼쪽 2시 방향
        case 10:        return .rightTurn        // 오른쪽 10시 방향
        case 11:        return .straight         // 직진
        case 12:        return .leftTurn         // 좌측 도로 진입
        case 13:        return .rightTurn        // 우측 도로 진입
        case 14:        return .straight         // 고가도로 진입
        case 15:        return .straight         // 지하차도 진입
        case 16:        return .rightTurn        // 로터리 시계방향
        case 17:        return .leftTurn         // 로터리 반시계방향
        // 도시고속 진입/출구
        case 43:        return .rightMerge       // 도시고속 입구 (우측)
        case 44:        return .rightExit        // 도시고속 출구 (우측)
        case 45:        return .leftMerge        // 도시고속 입구 (좌측)
        case 46:        return .leftExit         // 도시고속 출구 (좌측)
        case 47:        return .rightMerge       // 도시고속 입구
        case 48:        return .rightExit        // 도시고속 출구
        // 회전교차로 (방향별)
        case 70...79:   return turnTypeForRotary(kakaoType)
        // 분기 직진
        case 80:        return .straight         // 직진 (분기)
        case 81:        return .straight         // 오른쪽 직진 (분기)
        case 82:        return .straight         // 왼쪽 직진 (분기)
        // 출발지/목적지/경유지
        case 100:       return .straight         // 출발지
        case 101:       return .destination      // 목적지
        case 102...105: return .destination      // 경유지
        default:        return .unknown("kakao_type_\(kakaoType)")
        }
    }

    /// 회전교차로 type 코드 (70~79) → 방향 추정
    private static func turnTypeForRotary(_ type: Int) -> TurnType {
        switch type {
        case 71, 72, 73: return .rightTurn        // 시계방향 (1~3시)
        case 74, 75:     return .straight          // 직진 (12시 부근)
        case 76, 77, 78: return .leftTurn          // 반시계방향 (8~10시)
        case 79:         return .uTurn             // U턴
        default:         return .unknown("kakao_rotary_\(type)")
        }
    }

    /// Apple instructions 텍스트에서 TurnType 추론 (한국어 기기 기준)
    /// 실제 Apple API 데이터 기반으로 패턴 매칭 (우선순위 중요)
    static func from(appleInstructions: String) -> TurnType {
        let text = appleInstructions.lowercased()

        // 빈 문자열 = 출발 지점 (Apple 첫 step)
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .straight }

        // 한국어 키워드 (우선순위: 목적지 > 출구 > 진입 > 회전 > 직진)
        // 1. 목적지/도착 (가장 먼저 — "왼쪽에 목적지가 있음"에서 leftTurn 오매칭 방지)
        if text.contains("도착") || text.contains("목적지") { return .destination }

        // 2. 출구
        if text.contains("출구") { return .rightExit }

        // 3. 진입/합류
        if text.contains("진입") || text.contains("합류") { return .rightMerge }

        // 4. 회전
        if text.contains("우회전") { return .rightTurn }
        if text.contains("좌회전") { return .leftTurn }
        if text.contains("유턴") || text.contains("u턴") { return .uTurn }

        // 5. 방향 유지 / 완만한 회전 (Apple: "오른쪽 차선 유지", "완만히 우회전")
        if text.contains("오른쪽") { return .rightTurn }
        if text.contains("왼쪽") { return .leftTurn }

        // 6. 직진 / 계속 이동
        if text.contains("직진") || text.contains("계속") { return .straight }

        // 영어 키워드 (영어 기기 fallback)
        if text.contains("destination") || text.contains("arrive") { return .destination }
        if text.contains("exit") { return .rightExit }
        if text.contains("merge") { return .rightMerge }
        if text.contains("turn right") || text.contains("right turn") { return .rightTurn }
        if text.contains("turn left") || text.contains("left turn") { return .leftTurn }
        if text.contains("u-turn") || text.contains("u turn") { return .uTurn }
        if text.contains("right") { return .rightTurn }
        if text.contains("left") { return .leftTurn }
        if text.contains("straight") || text.contains("continue") { return .straight }

        return .unknown(appleInstructions)
    }
}
