import Testing
@testable import Navigation

struct TurnTypeTests {

    // MARK: - Kakao Type Code Mapping (실제 카카오 모빌리티 API 코드)

    @Test func kakaoType_start() {
        #expect(TurnType.from(kakaoType: 0) == .straight)
    }

    @Test func kakaoType_leftTurn() {
        #expect(TurnType.from(kakaoType: 1) == .leftTurn)
    }

    @Test func kakaoType_rightTurn() {
        #expect(TurnType.from(kakaoType: 2) == .rightTurn)
    }

    @Test func kakaoType_uTurn() {
        #expect(TurnType.from(kakaoType: 3) == .uTurn)
    }

    @Test func kakaoType_slightRight() {
        #expect(TurnType.from(kakaoType: 6) == .rightTurn)
    }

    @Test func kakaoType_cityHighwayExit() {
        #expect(TurnType.from(kakaoType: 44) == .rightExit)
    }

    @Test func kakaoType_cityHighwayEntrance() {
        #expect(TurnType.from(kakaoType: 47) == .rightMerge)
    }

    @Test func kakaoType_rotaryLeft() {
        #expect(TurnType.from(kakaoType: 77) == .leftTurn)
    }

    @Test func kakaoType_origin() {
        #expect(TurnType.from(kakaoType: 100) == .straight)
    }

    @Test func kakaoType_destination() {
        #expect(TurnType.from(kakaoType: 101) == .destination)
    }

    @Test func kakaoType_unknown() {
        let type = TurnType.from(kakaoType: 999)
        if case .unknown = type {
            // OK
        } else {
            Issue.record("Expected .unknown, got \(type)")
        }
    }

    // MARK: - Apple Instructions Parsing (실제 API 데이터 기반)

    @Test func apple_emptyString_isStart() {
        #expect(TurnType.from(appleInstructions: "") == .straight)
    }

    @Test func apple_rightTurn() {
        #expect(TurnType.from(appleInstructions: "방화대로(으)로 우회전") == .rightTurn)
    }

    @Test func apple_leftTurn() {
        #expect(TurnType.from(appleInstructions: "상암사거리에서 증산로(으)로 좌회전") == .leftTurn)
    }

    @Test func apple_exit() {
        #expect(TurnType.from(appleInstructions: "가양대교남단에서 가양대교 방면 출구로 나가기") == .rightExit)
    }

    @Test func apple_merge() {
        #expect(TurnType.from(appleInstructions: "올림픽대로(으)로 진입") == .rightMerge)
    }

    @Test func apple_destination_withDirection() {
        // "왼쪽에 목적지가 있음" → 목적지가 leftTurn보다 우선
        #expect(TurnType.from(appleInstructions: "왼쪽에 목적지가 있음") == .destination)
    }

    @Test func apple_continue() {
        #expect(TurnType.from(appleInstructions: "서울(구산) 방면으로 계속 이동") == .straight)
    }

    @Test func apple_keepLeft() {
        #expect(TurnType.from(appleInstructions: "왼쪽 차선을 유지하세요") == .leftTurn)
    }

    @Test func apple_gentleRight() {
        #expect(TurnType.from(appleInstructions: "서오릉로17길(으)로 완만히 우회전") == .rightTurn)
    }

    @Test func apple_uTurn() {
        #expect(TurnType.from(appleInstructions: "유턴하세요") == .uTurn)
    }

    // MARK: - Apple Instructions Parsing (English fallback)

    @Test func apple_rightTurn_english() {
        #expect(TurnType.from(appleInstructions: "Turn right onto Main Street") == .rightTurn)
    }

    @Test func apple_destination_english() {
        #expect(TurnType.from(appleInstructions: "The destination is on your left") == .destination)
    }

    // MARK: - Icon Names

    @Test func iconName_mapping() {
        #expect(TurnType.rightTurn.iconName == "arrow.turn.up.right")
        #expect(TurnType.leftTurn.iconName == "arrow.turn.up.left")
        #expect(TurnType.destination.iconName == "mappin.circle.fill")
        #expect(TurnType.straight.iconName == "arrow.up")
    }
}
