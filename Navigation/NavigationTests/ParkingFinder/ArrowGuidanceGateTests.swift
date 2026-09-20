import Testing
import Foundation
import simd
@testable import Navigation

/// v3 화살표 가이드 게이트 (spec 006 SC-101/102/103).
/// 현장 픽스처를 v3 규칙으로 리플레이해 "가동률 회복"과 "과신 미재발"을 함께 확인한다 —
/// 가동률만 보면 구조상 자명하게 통과하므로 반드시 묶어서 판정한다(SC-101 단서).
struct ArrowGuidanceGateTests {

    private func replay(_ name: String) throws -> ParkingEventReplayer.ReplayResult {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).ndjson")
        return try ParkingEventReplayer.replay(fileURL: url)
    }

    // MARK: - SC-101 가동률 회복

    @Test func restoresArrowOnMultiSignLot() throws {
        // 260919: 다중 표지판으로 '3'행이 전멸하고 구역 피치가 16.4m라 v2에서는 화살표 0%.
        // P2(추정기)만으로도 화살표가 되살아나야 한다 — 다만 이 세션의 관측 대부분은
        // 여전히 다중 표지판으로 제외되므로 SC-101 목표(60%)는 P3 클러스터 이후 달성된다
        let result = try replay("parking-20260919-180117-find")
        #expect(result.geometryEvaluated > 0)
        #expect(result.arrowAvailability > 0.25,
                "화살표 가동률 \(Int(result.arrowAvailability * 100))% — P2 최소선 미달")
    }

    @Test(.disabled("P3 표지판 클러스터 도입 후 활성화 — 현재는 모호 제외로 관측이 부족하다"))
    func meetsArrowAvailabilityTarget() throws {
        let result = try replay("parking-20260919-180117-find")
        #expect(result.arrowAvailability >= 0.6, "SC-101 미달: \(result.arrowAvailability)")
    }

    @Test func keepsArrowOnSuccessSessions() throws {
        // 도착에 성공했던 세션에서 화살표가 완전히 사라지지 않아야 한다.
        // (v2 규칙으로 리플레이하면 두 세션 모두 격자 안내가 0회였다 — 그 상태에서의 회복 확인)
        for name in ["parking-20260801-111450-find", "parking-20260911-102531-find"] {
            let result = try replay(name)
            #expect(result.arrowShown > 0, "\(name) 화살표 0회")
        }
    }

    // MARK: - SC-103 과신 미재발

    @Test func farExtrapolationStaysLowConfidence() throws {
        // J21: 관측 스팬 40.6m인데 표시 거리 88~102m. 잔차 0.10m라 잔차 기반 점수는 오히려 높아진다 —
        // 측방 불확실성(6스텝 외삽)이 백분율을 낮추고 거리 표시를 막아야 한다
        let result = try replay("parking-20260911-122157-find")
        #expect(result.maxPercentWhenShown < ParkingTuning.confidencePercentSolidThreshold,
                "J21 최대 백분율 \(result.maxPercentWhenShown)% — 과신 재발")
        #expect(result.distanceShown == 0, "J21에서 거리 표시 \(result.distanceShown)회 — 과신 재발")
    }

    @Test func contaminatedSessionStaysLowConfidence() throws {
        // J22: 다중 표지판 오염으로 30.3m 오차가 났던 세션
        let result = try replay("parking-20260911-121615-find")
        #expect(result.maxPercentWhenShown < 70, "J22 최대 백분율 \(result.maxPercentWhenShown)%")
    }

    // MARK: - 지표 덤프 (튜닝·PR 근거용)

    @Test func dumpsMetricsForAllFixtures() throws {
        let names = [
            "parking-20260710-180737-find", "parking-20260710-181820-find",
            "parking-20260801-111450-find", "parking-20260911-102531-find",
            "parking-20260911-121615-find", "parking-20260911-122157-find",
            "parking-20260919-180117-find",
        ]
        var lines: [String] = []
        for name in names {
            let r = try replay(name)
            lines.append(String(
                format: "%@: 평가 %d, 화살표 %d (%.0f%%), 거리표시 %d, 최대%% %d, 최대거리 %.1fm",
                name.replacingOccurrences(of: "parking-", with: ""),
                r.geometryEvaluated, r.arrowShown, r.arrowAvailability * 100,
                r.distanceShown, r.maxPercentWhenShown, r.maxDistanceWhenShown
            ))
        }
        let dump = lines.joined(separator: "\n")
        try? dump.write(toFile: NSTemporaryDirectory() + "arrow_gate_metrics.txt", atomically: true, encoding: .utf8)
        print("=== v3 게이트 지표 ===\n" + dump)
        #expect(!lines.isEmpty)
    }
}

/// FR-101 측방 각도 보장의 단위 검증 — 픽스처 없이 기하만
struct GuidanceGeometryTests {

    private let farUncertainty = GridEstimate.Uncertainty(unknownAxis: 5, fit: 1, expansion: 0)

    @Test func guaranteesDirectionWhenTargetIsFar() {
        let evaluation = GuidanceGeometry.evaluate(
            target: SIMD2(0, -60), uncertainty: farUncertainty,
            devicePosition: .zero, deviceForward: SIMD2(0, -1),
            observationSpan: 50, confidencePercent: 60
        )
        #expect(evaluation.isDirectionGuaranteed)
        #expect(abs(evaluation.arrowRadians) < 0.01)   // 정면
        #expect(evaluation.isDistanceDisplayable)
    }

    @Test func failsGuaranteeWhenUncertaintyRivalsDistance() {
        // 근접 구간: 불확실성이 거리에 필적하면 방위가 어느 쪽으로든 열린다 → 근접 모드 (FR-102)
        let evaluation = GuidanceGeometry.evaluate(
            target: SIMD2(0, -8), uncertainty: farUncertainty,
            devicePosition: .zero, deviceForward: SIMD2(0, -1),
            observationSpan: 50, confidencePercent: 60
        )
        #expect(!evaluation.isDirectionGuaranteed)
        #expect(evaluation.guaranteeAngle == .pi / 2)
    }

    @Test func hidesDistanceBeyondObservationSpan() {
        // FR-106: 관측 배치 규모를 넘는 거리는 방향만
        let evaluation = GuidanceGeometry.evaluate(
            target: SIMD2(0, -90), uncertainty: GridEstimate.Uncertainty(unknownAxis: 0, fit: 2, expansion: 0),
            devicePosition: .zero, deviceForward: SIMD2(0, -1),
            observationSpan: 40, confidencePercent: 70
        )
        #expect(evaluation.isDirectionGuaranteed)
        #expect(!evaluation.isDistanceDisplayable)
    }

    @Test func hidesDistanceBelowSolidThreshold() {
        let evaluation = GuidanceGeometry.evaluate(
            target: SIMD2(0, -30), uncertainty: GridEstimate.Uncertainty(unknownAxis: 0, fit: 1, expansion: 0),
            devicePosition: .zero, deviceForward: SIMD2(0, -1),
            observationSpan: 50, confidencePercent: 20
        )
        #expect(evaluation.isDirectionGuaranteed)
        #expect(!evaluation.isDistanceDisplayable)
    }

    @Test func arrowSignIsClockwisePositive() {
        // 전방 -z, 목표가 +x(오른쪽) → 시계방향 양수
        let evaluation = GuidanceGeometry.evaluate(
            target: SIMD2(30, 0), uncertainty: GridEstimate.Uncertainty(),
            devicePosition: .zero, deviceForward: SIMD2(0, -1),
            observationSpan: 50, confidencePercent: 80
        )
        #expect(evaluation.arrowRadians > 0)
    }
}
