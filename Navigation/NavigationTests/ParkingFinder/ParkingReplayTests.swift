import Testing
import Foundation
@testable import Navigation

/// 리플레이 계약 (DR-003, SC-009): codeObserved 스트림 재계산 = 기록된 gridUpdated.
/// 합성 로그로 메커니즘을 고정 — 실주차장 로그 픽스처는 T044에서 추가.
struct ParkingReplayTests {

    /// GridEstimatorTests의 3점 아핀 케이스와 동일 기하:
    /// A-1=(3,0), A-2=(6,0), B-1=(3,5) → 목표 B-2 = (6,5)
    /// (B-3은 외삽 레버 3.0 > 2.5로 G1 가드가 차단 — 설계 개정 v2)
    private func syntheticLog(recordedStage: String, recordedTarget: [Double]) -> String {
        """
        {"t":0,"e":"sessionStart","mode":"find","target":{"raw":"B-2","floor":null,"skeleton":"Z-N"},"neighbors":[]}
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
            ndjson: syntheticLog(recordedStage: "gridGuidance", recordedTarget: [6, 5])
        )
        #expect(result.isConsistent)
        #expect(result.comparedCount == 1)
        #expect(result.recomputedCount > 0)
        // 재계산된 최종 추정도 기록과 같은 목표 위치
        let target = try #require(result.finalEstimate?.targetPosition)
        #expect(abs(target.x - 6) < 0.05)
        #expect(abs(target.y - 5) < 0.05)
    }

    @Test func staleRecordedStageIsDetectedAsMismatch() throws {
        // 기록이 잘못된(구버전 로직) 로그 — 리플레이가 회귀/불일치를 감지해야 함
        let result = try ParkingEventReplayer.replay(
            ndjson: syntheticLog(recordedStage: "degraded", recordedTarget: [6, 5])
        )
        #expect(!result.isConsistent)
        #expect(result.mismatches.count == 1)
    }

    @Test func recordedTargetDriftIsDetected() throws {
        let result = try ParkingEventReplayer.replay(
            ndjson: syntheticLog(recordedStage: "gridGuidance", recordedTarget: [9, 5])
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

    @Test func fieldLogFind1BlockedByLeverGuard() throws {
        // 목표 "9", 관측 "2"·"3" — 인접 쌍에서 6스텝 외삽(레버 9.2)은 이제 G1이 차단 (설계 개정 v2).
        // 개선 전 이 세션의 축 안내가 바로 "과소 관측 원거리 외삽" 부류였다
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260710-180737-find.ndjson")
        )
        #expect(result.recomputedCount > 0)
        #expect(result.finalEstimate?.stage == .needMoreObservation(missing: .number),
                "\(String(describing: result.finalEstimate?.stage))")
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
        // 의도된 차이만 존재: 개선 전 과신 안내가 정직한 안내로만 바뀜 (신선도 260814 + 모호 표지판 제외 260911 —
        // F3은 4.9m 위치 점프로 모호 처리). 재계산이 새로 격자 안내를 만드는 방향의 차이는 없어야 한다.
        #expect(!result.mismatches.isEmpty)
        #expect(result.mismatches.allSatisfy { !$0.contains("재계산=gridGuidance") }, "\(result.mismatches.prefix(5))")
        // 최종(t≈70s): 낡은·모호 좌표가 제외되어 searching
        // (개선 전엔 이 시점에 10.2m 틀린 화살표를 high 신뢰도로 표시했다 — 도착은 직접 인식으로 별도 확정)
        #expect(result.finalEstimate?.stage == .searching,
                "\(String(describing: result.finalEstimate?.stage))")
    }

    // MARK: - 260911 3차 현장 픽스처 (다중 표지판 주차장 — 동일 코드 7~13m 복수 위치)

    @Test func fieldLog260911Session1KeepsGridWithAmbiguousExclusion() throws {
        // H22 세션(58s, 도착 성공): G22만 13.3m 점프 → 모호 제외, 격자는 유지
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260911-102531-find.ndjson")
        )
        #expect(result.comparedCount == 76)
        #expect(result.mismatches.count == 11, "\(result.mismatches.prefix(4))")
        // 설계 개정 v2: 최종 시점(관측 E·G구역, 목표 H22)은 레버 가드가 격자 화살표 대신 구역 관측 안내로
        #expect(result.finalEstimate?.stage == .needMoreObservation(missing: .zone),
                "\(String(describing: result.finalEstimate?.stage))")
    }

    @Test func fieldLog260911Session2SuppressesCorruptedAxis() throws {
        // J22 세션(106s): J23·J24·G25가 8~11m 복수 표지판 → 전부 모호 제외.
        // 개선 전엔 도착 순간 30.3m 틀린 축 안내 — 재계산은 격자 안내를 만들지 않아야 한다
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260911-121615-find.ndjson")
        )
        #expect(result.comparedCount == 120)
        #expect(result.mismatches.allSatisfy { !$0.contains("재계산=gridGuidance") && !$0.contains("재계산=axisGuidance") },
                "\(result.mismatches.prefix(4))")
        #expect(result.finalEstimate?.stage == .searching)
    }

    @Test func fieldLog260911Session3AllTwinSignsLot() throws {
        // J21 세션(60s): B~D구역 전 코드가 7.3~8.2m 쌍둥이 표지판 → 대부분 모호 제외.
        // 격자 대신 그라디언트 힌트(구역 안내)가 담당하는 케이스 — 재계산 최종은 searching
        let result = try ParkingEventReplayer.replay(
            fileURL: fieldLog("parking-20260911-122157-find.ndjson")
        )
        #expect(result.comparedCount == 117)
        #expect(result.finalEstimate?.stage == .searching)
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-test-\(UUID().uuidString).ndjson")
        try syntheticLog(recordedStage: "gridGuidance", recordedTarget: [6, 5])
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try ParkingEventReplayer.replay(fileURL: url)
        #expect(result.isConsistent)
    }
}
