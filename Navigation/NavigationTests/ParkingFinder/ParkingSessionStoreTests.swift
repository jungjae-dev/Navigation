import Testing
import SwiftData
@testable import Navigation

/// 주차 세션 수명주기 — 활성 ≤1, 대체, 완료 보관 1건 (FR-019/020/021)
/// in-memory 컨테이너로 DataService를 구성해 검증.
struct ParkingSessionStoreTests {

    private func makeInMemoryService() throws -> DataService {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ParkingSessionRecord.self, configurations: config)
        DataService.shared.configure(with: container)
        return DataService.shared
    }

    private func makeRecord(code: String, floor: String? = "B2") -> ParkingSessionRecord {
        ParkingSessionRecord(
            targetCodeRaw: code,
            floorToken: floor,
            floorSource: .code,
            zoneToken: "A",
            numberValue: 3,
            templateSkeleton: "F-Z-N"
        )
    }

    @Test func savesAndFetchesActiveSession() throws {
        let service = try makeInMemoryService()

        service.saveParkingSession(makeRecord(code: "B2-A-3"))

        let active = service.fetchActiveParkingSession()
        #expect(active?.targetCodeRaw == "B2-A-3")
        #expect(active?.status == .active)
    }

    @Test func noActiveSessionInitially() throws {
        let service = try makeInMemoryService()
        #expect(service.fetchActiveParkingSession() == nil)
    }

    @Test func newSessionReplacesExistingActive() throws {
        let service = try makeInMemoryService()

        service.saveParkingSession(makeRecord(code: "B2-A-3"))
        service.saveParkingSession(makeRecord(code: "B1-C-7"))

        let active = service.fetchActiveParkingSession()
        #expect(active?.targetCodeRaw == "B1-C-7")
    }

    @Test func completingSessionClearsActive() throws {
        let service = try makeInMemoryService()

        let record = makeRecord(code: "B2-A-3")
        service.saveParkingSession(record)
        service.completeParkingSession(record, by: "manual")

        #expect(service.fetchActiveParkingSession() == nil)
        #expect(record.status == .completed)
        #expect(record.completedAt != nil)
    }

    @Test func retainsOnlyMostRecentCompletedSession() throws {
        let service = try makeInMemoryService()

        let first = makeRecord(code: "B2-A-3")
        service.saveParkingSession(first)
        service.completeParkingSession(first, by: "manual")

        let second = makeRecord(code: "B1-C-7")
        service.saveParkingSession(second)
        service.completeParkingSession(second, by: "target-recognition")

        // 완료 기록은 최근 1건만 보관 — 첫 기록은 삭제됨
        #expect(service.fetchActiveParkingSession() == nil)
        #expect(first.modelContext == nil)   // 컨텍스트에서 제거됨
        #expect(second.modelContext != nil)
    }

    @Test func swapTargetPromotesNeighborAndDemotesOldTarget() throws {
        let service = try makeInMemoryService()

        let record = ParkingSessionRecord(
            targetCodeRaw: "B2-A-3",
            floorToken: "B2",
            floorSource: .code,
            zoneToken: "A",
            numberValue: 3,
            templateSkeleton: "F-Z-N",
            neighbors: [
                NeighborCode(codeRaw: "B2-A-4", zoneToken: "A", numberValue: 4, distanceToTarget: 3.1),
                NeighborCode(codeRaw: "B2-B-3", zoneToken: "B", numberValue: 3, distanceToTarget: 5.2),
            ]
        )
        service.saveParkingSession(record)

        service.swapParkingTarget(record, to: record.neighbors[0])

        #expect(record.targetCodeRaw == "B2-A-4")
        #expect(record.numberValue == 4)
        // 이전 목표는 인접으로 강등 — 교체 대상과의 거리는 대칭이라 유지
        let demoted = record.neighbors.first { $0.codeRaw == "B2-A-3" }
        #expect(demoted?.distanceToTarget == 3.1)
        // 나머지 인접의 거리는 새 목표 기준 미지 → nil
        let other = record.neighbors.first { $0.codeRaw == "B2-B-3" }
        #expect(other?.distanceToTarget == nil)
        // 층·스켈레톤은 같은 스캔이므로 유지
        #expect(record.floorToken == "B2")
        #expect(record.templateSkeleton == "F-Z-N")
    }

    @Test func neighborsRoundTripThroughJSON() throws {
        let neighbors = [
            NeighborCode(codeRaw: "A-4", zoneToken: "A", numberValue: 4, distanceToTarget: 3.1),
            NeighborCode(codeRaw: "B-3", zoneToken: "B", numberValue: 3, distanceToTarget: nil),
        ]
        let record = ParkingSessionRecord(
            targetCodeRaw: "A-3",
            floorToken: nil,
            floorSource: .manual,
            zoneToken: "A",
            numberValue: 3,
            templateSkeleton: "Z-N",
            neighbors: neighbors
        )
        #expect(record.neighbors == neighbors)
    }
}
