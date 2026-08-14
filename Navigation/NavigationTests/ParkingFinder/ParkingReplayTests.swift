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

    @Test func fieldLogFind3ZNLotReplaysWithFreshnessImprovement() throws {
        // 260801 수집 — ZN 주차장, 최초 도착 확정 성공 세션. 단 목표 추정 오차 10.2m가 있었고
        // 원인(낡은 F3/F4 좌표 + 4점 과신)을 신선도 필터·신뢰도 상한으로 개선했다.
        // 이 로그의 기록은 개선 전 로직 산출물 — 후반부(낡은 관측 잔류 구간)에서
        // 재계산이 의도적으로 달라지며, 달라지는 방식은 전부 "gridGuidance → 정직한 추가 관측 안내"여야 한다.
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260801-111450-find.ndjson")
        )
        #expect(result.comparedCount == 168)
        // 의도된 차이만 존재: 기록=gridGuidance(개선 전 과신)가 정직한 안내(needMore/searching)로 바뀜
        #expect(!result.mismatches.isEmpty)
        #expect(result.mismatches.allSatisfy { $0.contains("기록=gridGuidance") }, "\(result.mismatches.prefix(5))")
        // 최종(t≈70s): 낡은 좌표가 모두 제외되고 신선한 관측이 D3 하나뿐 → searching
        // (개선 전엔 이 시점에 10.2m 틀린 화살표를 high 신뢰도로 표시했다 — 도착은 직접 인식으로 별도 확정)
        #expect(result.finalEstimate?.stage == .searching,
                "\(String(describing: result.finalEstimate?.stage))")
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
