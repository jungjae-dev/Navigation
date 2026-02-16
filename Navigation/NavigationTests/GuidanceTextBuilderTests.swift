import Testing
import Foundation
@testable import Navigation

struct GuidanceTextBuilderTests {

    // MARK: - buildText

    @Test func approachingText() {
        let text = GuidanceTextBuilder.buildText(
            for: .approaching(distance: 500, instruction: "우회전")
        )
        #expect(text == "500미터 앞에서 우회전하세요")
    }

    @Test func approachingWithKilometers() {
        let text = GuidanceTextBuilder.buildText(
            for: .approaching(distance: 1500, instruction: "좌회전")
        )
        #expect(text == "1.5킬로미터 앞에서 좌회전하세요")
    }

    @Test func imminentText() {
        let text = GuidanceTextBuilder.buildText(for: .imminent(instruction: "좌회전"))
        #expect(text == "잠시 후 좌회전하세요")
    }

    @Test func imminentAlreadyHasSuffix() {
        let text = GuidanceTextBuilder.buildText(
            for: .imminent(instruction: "좌회전하세요")
        )
        #expect(text == "잠시 후 좌회전하세요")
    }

    @Test func departedText() {
        let text = GuidanceTextBuilder.buildText(for: .departed)
        #expect(text == "경로를 이탈했습니다")
    }

    @Test func reroutingText() {
        let text = GuidanceTextBuilder.buildText(for: .rerouting)
        #expect(text == "새로운 경로를 탐색합니다")
    }

    @Test func reroutedText() {
        let text = GuidanceTextBuilder.buildText(for: .rerouted)
        #expect(text == "새로운 경로로 안내합니다")
    }

    @Test func arrivedText() {
        let text = GuidanceTextBuilder.buildText(for: .arrived)
        #expect(text == "목적지에 도착했습니다")
    }

    @Test func straightAheadText() {
        let text = GuidanceTextBuilder.buildText(for: .straightAhead(distance: 300))
        #expect(text == "300미터 직진하세요")
    }

    // MARK: - formatDistanceForVoice

    @Test func formatDistanceUnder100() {
        let result = GuidanceTextBuilder.formatDistanceForVoice(50)
        #expect(result == "50미터")
    }

    @Test func formatDistanceUnder1000() {
        let result = GuidanceTextBuilder.formatDistanceForVoice(350)
        #expect(result == "300미터")
    }

    @Test func formatDistanceExactKilometer() {
        let result = GuidanceTextBuilder.formatDistanceForVoice(2000)
        #expect(result == "2킬로미터")
    }

    @Test func formatDistanceFractionalKilometer() {
        let result = GuidanceTextBuilder.formatDistanceForVoice(1500)
        #expect(result == "1.5킬로미터")
    }

    @Test func formatDistanceRounded() {
        let result = GuidanceTextBuilder.formatDistanceForVoice(750)
        #expect(result == "700미터")
    }

    // MARK: - iconNameForInstruction

    @Test func iconRightTurn() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("우회전하세요") == "arrow.turn.up.right")
    }

    @Test func iconLeftTurn() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("좌회전하세요") == "arrow.turn.up.left")
    }

    @Test func iconUTurn() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("유턴하세요") == "arrow.uturn.left")
    }

    @Test func iconMerge() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("합류하세요") == "arrow.merge")
    }

    @Test func iconExit() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("출구로 나가세요") == "arrow.up.right")
    }

    @Test func iconRamp() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("램프 진입") == "arrow.up.right")
    }

    @Test func iconDestination() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("목적지에 도착") == "flag.fill")
    }

    @Test func iconStraight() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("직진하세요") == "arrow.up")
    }

    @Test func iconEnglishRight() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("Turn right") == "arrow.turn.up.right")
    }

    @Test func iconEnglishLeft() {
        #expect(GuidanceTextBuilder.iconNameForInstruction("Turn left") == "arrow.turn.up.left")
    }
}
