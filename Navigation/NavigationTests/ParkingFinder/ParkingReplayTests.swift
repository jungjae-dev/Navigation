import Testing
import Foundation
@testable import Navigation

/// 리플레이 계약 (DR-003, SC-009): codeObserved 스트림 재계산 = 기록된 gridUpdated.
/// 합성 로그로 메커니즘을 고정 — 실주차장 로그 픽스처는 T044에서 추가.
struct ParkingReplayTests {

    /// GridEstimatorTests의 3점 아핀 케이스와 동일 기하:
    /// A-1=(3,0), A-2=(6,0), B-1=(3,5) → 목표 B-3 = (9,5)
    private func syntheticLog(recordedStage: String, recordedTarget: [Double]) -> String {
        """
        {"t":0,"e":"sessionStart","mode":"find","target":{"raw":"B-3","floor":null,"skeleton":"Z-N"},"neighbors":[]}
        {"t":1.0,"e":"codeObserved","raw":"A-1","conf":0.9,"hit":1,"pos":[3,0,0]}
        {"t":1.5,"e":"codeObserved","raw":"A-1","conf":0.9,"hit":2,"pos":[3,0,0]}
        {"t":2.0,"e":"codeObserved","raw":"A-2","conf":0.9,"hit":1,"pos":[6,0,0]}
        {"t":2.5,"e":"codeObserved","raw":"A-2","conf":0.9,"hit":2,"pos":[6,0,0]}
        {"t":3.0,"e":"codeObserved","raw":"B-1","conf":0.9,"hit":1,"pos":[3,0,5]}
        {"t":3.5,"e":"codeObserved","raw":"B-1","conf":0.9,"hit":2,"pos":[3,0,5]}
        {"t":3.6,"e":"gridUpdated","stage":"\(recordedStage)","obs":3,"residualRMS":0,"targetEst":\(recordedTarget),"confidence":1}
        """
    }

    @Test func consistentLogReplaysWithoutMismatch() throws {
        let result = try ParkingEventReplayer.replay(
            ndjson: syntheticLog(recordedStage: "gridGuidance", recordedTarget: [9, 5])
        )
        #expect(result.isConsistent)
        #expect(result.comparedCount == 1)
        #expect(result.recomputedCount > 0)
        // 재계산된 최종 추정도 기록과 같은 목표 위치
        let target = try #require(result.finalEstimate?.targetPosition)
        #expect(abs(target.x - 9) < 0.05)
        #expect(abs(target.y - 5) < 0.05)
    }

    @Test func staleRecordedStageIsDetectedAsMismatch() throws {
        // 기록이 잘못된(구버전 로직) 로그 — 리플레이가 회귀/불일치를 감지해야 함
        let result = try ParkingEventReplayer.replay(
            ndjson: syntheticLog(recordedStage: "degraded", recordedTarget: [9, 5])
        )
        #expect(!result.isConsistent)
        #expect(result.mismatches.count == 1)
    }

    @Test func recordedTargetDriftIsDetected() throws {
        let result = try ParkingEventReplayer.replay(
            ndjson: syntheticLog(recordedStage: "gridGuidance", recordedTarget: [12, 5])
        )
        #expect(!result.isConsistent)
    }

    @Test func missingSessionStartThrows() {
        #expect(throws: ParkingEventReplayer.ReplayError.self) {
            try ParkingEventReplayer.replay(ndjson: #"{"t":0,"e":"codeObserved","raw":"A-1","hit":2,"pos":[0,0,0],"conf":0.9}"#)
        }
    }

    // MARK: - 실주차장 현장 로그 픽스처 (T044, 260710 수집 — 번호 단독 "N" 스켈레톤 주차장)

    private func fieldLog(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    @Test func fieldLogFind1ReplaysToAxisGuidance() throws {
        // 목표 "9", 관측 "2"·"3" → 번호축 안내까지 도달했던 세션
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260710-180737-find.ndjson")
        )
        #expect(result.recomputedCount > 0)
        if case .axisGuidance = result.finalEstimate?.stage {} else {
            Issue.record("expected axisGuidance, got \(String(describing: result.finalEstimate?.stage))")
        }
    }

    @Test func fieldLogFind2ReplaysToAxisGuidance() throws {
        // 목표 "09"(선행 0), 관측 "03"/"3"/"10" — 선행 0 정규화 후에도 축 안내 유지 확인
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260710-181820-find.ndjson")
        )
        #expect(result.recomputedCount > 0)
        if case .axisGuidance = result.finalEstimate?.stage {} else {
            Issue.record("expected axisGuidance, got \(String(describing: result.finalEstimate?.stage))")
        }
    }

    @Test func fieldLogFind3ZNLotReplaysConsistently() throws {
        // 260801 수집 — 구역+번호(ZN) 주차장, 최초 도착 확정 성공 세션 (70s, 관측 11종)
        // searching → needMore(zone) → gridGuidance 전 과정과 목표 외삽이 기록과 일치해야 함
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260801-111450-find.ndjson")
        )
        #expect(result.comparedCount == 168)
        #expect(result.isConsistent, "\(result.mismatches.prefix(5))")
        if case .gridGuidance = result.finalEstimate?.stage {} else {
            Issue.record("expected gridGuidance, got \(String(describing: result.finalEstimate?.stage))")
        }
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-test-\(UUID().uuidString).ndjson")
        try syntheticLog(recordedStage: "gridGuidance", recordedTarget: [9, 5])
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try ParkingEventReplayer.replay(fileURL: url)
        #expect(result.isConsistent)
    }
}
