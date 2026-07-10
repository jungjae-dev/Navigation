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
