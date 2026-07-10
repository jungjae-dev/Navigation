import Testing
@testable import Navigation

/// 기둥 코드 파서 — 토큰화·스켈레톤·템플릿 매칭 (FR-006/008, R4)
struct PillarCodeParserTests {

    // MARK: - 표준 패턴 파싱

    @Test func parsesFloorZoneNumber() {
        let code = PillarCodeParser.parse("B2-A-3")
        #expect(code?.floorToken == "B2")
        #expect(code?.zoneToken == "A")
        #expect(code?.zoneIndex == 0)
        #expect(code?.numberValue == 3)
        #expect(code?.skeleton == "F-Z-N")
    }

    @Test func parsesZoneNumberWithoutFloor() {
        let code = PillarCodeParser.parse("A-3")
        #expect(code?.floorToken == nil)
        #expect(code?.zoneToken == "A")
        #expect(code?.numberValue == 3)
        #expect(code?.skeleton == "Z-N")
    }

    @Test func parsesHangulZoneWithJihaFloor() {
        let code = PillarCodeParser.parse("지하2 가-15")
        #expect(code?.floorToken == "B2")   // 지하2 → B2 정규화
        #expect(code?.zoneToken == "가")
        #expect(code?.zoneIndex == 0)
        #expect(code?.numberValue == 15)
        #expect(code?.skeleton == "F-Z-N")
    }

    @Test func parsesCombinedZoneNumber() {
        let code = PillarCodeParser.parse("가15")
        #expect(code?.zoneToken == "가")
        #expect(code?.numberValue == 15)
        #expect(code?.skeleton == "ZN")
    }

    @Test func singleSegmentB2IsZoneNumberNotFloor() {
        // "B2" 단독은 층이 아니라 구역 B + 번호 2로 해석 (중의성 규칙)
        let code = PillarCodeParser.parse("B2")
        #expect(code?.floorToken == nil)
        #expect(code?.zoneToken == "B")
        #expect(code?.numberValue == 2)
        #expect(code?.skeleton == "ZN")
    }

    @Test func parsesFloorCombinedZN() {
        let code = PillarCodeParser.parse("B3 C12")
        #expect(code?.floorToken == "B3")
        #expect(code?.zoneToken == "C")
        #expect(code?.numberValue == 12)
        #expect(code?.skeleton == "F-ZN")
    }

    @Test func normalizesSeparatorVariants() {
        #expect(PillarCodeParser.parse("B2·A·3")?.raw == "B2-A-3")
        #expect(PillarCodeParser.parse(" b2 / a / 3 ")?.raw == "B2-A-3")
    }

    @Test func zoneIndexOrdering() {
        #expect(PillarCodeParser.parse("C-1")?.zoneIndex == 2)
        #expect(PillarCodeParser.parse("다-1")?.zoneIndex == 2)
    }

    // MARK: - 오검출 기각 (FR-008)

    @Test func rejectsLicensePlate() {
        #expect(PillarCodeParser.parse("12가3456") == nil)
        #expect(PillarCodeParser.parse("123가4567") == nil)
    }

    @Test func rejectsSignageText() {
        #expect(PillarCodeParser.parse("출구") == nil)
        #expect(PillarCodeParser.parse("전방 30M 서행") == nil)
        #expect(PillarCodeParser.parse("") == nil)
    }

    @Test func rejectsTooLongText() {
        #expect(PillarCodeParser.parse("B2-A-3-EXTRA-LONG-TEXT") == nil)
    }

    // MARK: - 스켈레톤 유도·템플릿 매칭

    @Test func derivesMostFrequentSkeleton() {
        let codes = ["B2-A-3", "B2-A-4", "B-3"].compactMap { PillarCodeParser.parse($0) }
        #expect(PillarCodeParser.skeleton(fromRegistered: codes) == "F-Z-N")
    }

    @Test func singleManualCodeSeedsSkeleton() {
        // 수동 등록: 코드 1개에서 스켈레톤 유도 (FR-008)
        let code = PillarCodeParser.parse("A-3").map { [$0] } ?? []
        #expect(PillarCodeParser.skeleton(fromRegistered: code) == "Z-N")
    }

    @Test func emptyRegistrationYieldsRawSkeleton() {
        #expect(PillarCodeParser.skeleton(fromRegistered: []) == PillarCodeParser.rawSkeleton)
    }

    @Test func templateMatchesSameStructure() {
        let template = "F-Z-N"
        let candidate = PillarCodeParser.parse("B1-C-7")!
        #expect(PillarCodeParser.matchesTemplate(candidate, skeleton: template))
    }

    @Test func templateIsLenientAboutFloorPresence() {
        // 층 표기가 기둥마다 생략되는 주차장 대응 — F 유무는 관대
        let candidate = PillarCodeParser.parse("C-7")!
        #expect(PillarCodeParser.matchesTemplate(candidate, skeleton: "F-Z-N"))
    }

    @Test func templateRejectsDifferentStructure() {
        let candidate = PillarCodeParser.parse("가15")!   // ZN
        #expect(!PillarCodeParser.matchesTemplate(candidate, skeleton: "F-Z-N"))
    }

    @Test func rawSkeletonMatchesNothing() {
        let candidate = PillarCodeParser.parse("B2-A-3")!
        #expect(!PillarCodeParser.matchesTemplate(candidate, skeleton: PillarCodeParser.rawSkeleton))
    }

    // MARK: - OCR 오인식 관련 경계

    @Test func gridUsableRequiresZoneOrNumber() {
        #expect(PillarCodeParser.parse("B2-A-3")?.isGridUsable == true)
    }
}
