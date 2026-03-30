import Testing
@testable import Navigation

struct TurnTypeTests {

    // MARK: - Kakao Type Code Mapping

    @Test func kakaoType_straight() {
        #expect(TurnType.from(kakaoType: 11) == .straight)
    }

    @Test func kakaoType_leftTurn() {
        #expect(TurnType.from(kakaoType: 12) == .leftTurn)
    }

    @Test func kakaoType_rightTurn() {
        #expect(TurnType.from(kakaoType: 13) == .rightTurn)
    }

    @Test func kakaoType_uTurn() {
        #expect(TurnType.from(kakaoType: 14) == .uTurn)
    }

    @Test func kakaoType_destination() {
        #expect(TurnType.from(kakaoType: 201) == .destination)
    }

    @Test func kakaoType_highway() {
        let type = TurnType.from(kakaoType: 100)
        #expect(type == .straight)
    }

    @Test func kakaoType_unknown() {
        let type = TurnType.from(kakaoType: 999)
        if case .unknown = type {
            // OK
        } else {
            Issue.record("Expected .unknown, got \(type)")
        }
    }

    // MARK: - Apple Instructions Parsing (Korean)

    @Test func apple_rightTurn_korean() {
        #expect(TurnType.from(appleInstructions: "테헤란로에서 우회전") == .rightTurn)
    }

    @Test func apple_leftTurn_korean() {
        #expect(TurnType.from(appleInstructions: "좌회전하세요") == .leftTurn)
    }

    @Test func apple_uTurn_korean() {
        #expect(TurnType.from(appleInstructions: "유턴하세요") == .uTurn)
    }

    @Test func apple_destination_korean() {
        #expect(TurnType.from(appleInstructions: "목적지에 도착했습니다") == .destination)
    }

    @Test func apple_straight_korean() {
        #expect(TurnType.from(appleInstructions: "직진하세요") == .straight)
    }

    // MARK: - Apple Instructions Parsing (English fallback)

    @Test func apple_rightTurn_english() {
        #expect(TurnType.from(appleInstructions: "Turn right onto Main Street") == .rightTurn)
    }

    @Test func apple_leftTurn_english() {
        #expect(TurnType.from(appleInstructions: "Turn left") == .leftTurn)
    }

    @Test func apple_unknown() {
        let type = TurnType.from(appleInstructions: "")
        if case .unknown = type {
            // OK
        } else {
            Issue.record("Expected .unknown for empty string, got \(type)")
        }
    }

    // MARK: - Icon Names

    @Test func iconName_mapping() {
        #expect(TurnType.rightTurn.iconName == "arrow.turn.up.right")
        #expect(TurnType.leftTurn.iconName == "arrow.turn.up.left")
        #expect(TurnType.destination.iconName == "mappin.circle.fill")
        #expect(TurnType.straight.iconName == "arrow.up")
    }
}
