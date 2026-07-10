import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.parking", category: "ParkingFinder")

/// 주차 세션 수명주기 상태 — 요약(허브) 화면과 코디네이터가 공유 (T011).
final class ParkingFinderViewModel {

    let activeSession = CurrentValueSubject<ParkingSessionRecord?, Never>(nil)

    init() {
        refresh()
    }

    func refresh() {
        activeSession.send(DataService.shared.fetchActiveParkingSession())
    }

    /// 도착 확정 또는 수동 "찾았어요" (FR-021)
    func complete(by trigger: String) {
        guard let record = activeSession.value else { return }
        DataService.shared.completeParkingSession(record, by: trigger)
        activeSession.send(nil)
    }

    /// 저장 직후 목표 즉시 교체 (FR-002a)
    func swapTarget(to neighbor: NeighborCode) {
        guard let record = activeSession.value else { return }
        DataService.shared.swapParkingTarget(record, to: neighbor)
        activeSession.send(record)
    }

    /// 새 위치 등록 진입 전 안내가 필요한지 (FR-019)
    var hasActiveSession: Bool { activeSession.value != nil }

    func adopt(_ record: ParkingSessionRecord) {
        logger.info("[ParkingFinder] session saved: \(record.targetCodeRaw) floor=\(record.floorToken ?? "?")(\(record.floorSourceRaw)) photos=\(record.photoPaths.count)")
        activeSession.send(record)
    }
}
