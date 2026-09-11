import Testing
import Foundation
import simd
@testable import Navigation

/// 단계적 격자 추정 — 1D/2D/혼합축/강등·복귀/도착 (FR-009/012/013, R5)
struct GridEstimatorTests {

    private func obs(_ code: String, zone: Int?, num: Int?, _ x: Double, _ y: Double) -> GridObservation {
        GridObservation(codeRaw: code, zoneIndex: zone, numberValue: num, position: SIMD2(x, y))
    }

    // MARK: - 관측 부족

    @Test func singleObservationIsSearching() {
        var estimator = GridEstimator()
        let result = estimator.estimate(
            observations: [obs("A-5", zone: 0, num: 5, 0, 0)],
            targetZoneIndex: 0, targetNumber: 3
        )
        #expect(result.stage == .searching)
        #expect(result.targetPosition == nil)
    }

    // MARK: - 2개: 단일축 1D (FR-009b)

    @Test func sameZonePairGivesNumberAxisGuidance() {
        var estimator = GridEstimator()
        // A-5 (0,0), A-7 (6,0) → 번호 1스텝 = (3,0). 목표 A-3 → (-6, 0)
        let result = estimator.estimate(
            observations: [
                obs("A-5", zone: 0, num: 5, 0, 0),
                obs("A-7", zone: 0, num: 7, 6, 0),
            ],
            targetZoneIndex: 0, targetNumber: 3
        )
        #expect(result.stage == .axisGuidance(axis: .number))
        let target = try! #require(result.targetPosition)
        #expect(abs(target.x - (-6)) < 0.01)
        #expect(abs(target.y) < 0.01)
    }

    @Test func sameNumberPairGivesZoneAxisGuidance() {
        var estimator = GridEstimator()
        // A-3 (0,0), C-3 (0,8) → 구역 1스텝 = (0,4). 목표 B-3 → (0,4)
        let result = estimator.estimate(
            observations: [
                obs("A-3", zone: 0, num: 3, 0, 0),
                obs("C-3", zone: 2, num: 3, 0, 8),
            ],
            targetZoneIndex: 1, targetNumber: 3
        )
        #expect(result.stage == .axisGuidance(axis: .zone))
        let target = try! #require(result.targetPosition)
        #expect(abs(target.y - 4) < 0.01)
    }

    // MARK: - 2개: 분해 불가 (FR-009b/c)

    @Test func mixedAxisPairNeedsMoreObservation() {
        var estimator = GridEstimator()
        let result = estimator.estimate(
            observations: [
                obs("A-5", zone: 0, num: 5, 0, 0),
                obs("B-7", zone: 1, num: 7, 6, 4),
            ],
            targetZoneIndex: 0, targetNumber: 3
        )
        guard case .needMoreObservation = result.stage else {
            Issue.record("expected needMoreObservation, got \(result.stage)")
            return
        }
        #expect(result.targetPosition == nil)
    }

    @Test func numberAxisKnownButTargetInDifferentZone() {
        var estimator = GridEstimator()
        // 번호축은 확보했으나 목표(B구역)가 축 밖 → 구역축 관측 요청
        let result = estimator.estimate(
            observations: [
                obs("A-5", zone: 0, num: 5, 0, 0),
                obs("A-7", zone: 0, num: 7, 6, 0),
            ],
            targetZoneIndex: 1, targetNumber: 3
        )
        #expect(result.stage == .needMoreObservation(missing: .zone))
    }

    // MARK: - 3개+: 2D 아핀 (FR-009d)

    @Test func threeNonCollinearObservationsGiveGridGuidance() {
        var estimator = GridEstimator()
        // 격자: zoneVec=(0,5), numVec=(3,0), origin=(0,0)
        // A-1=(3,0), A-2=(6,0), B-1=(3,5) → 목표 B-2 = (6,5)
        // (목표 B-3은 레버 3.0 > 2.5로 G1이 차단 — leverGuardBlocksFarExtrapolation에서 검증)
        let result = estimator.estimate(
            observations: [
                obs("A-1", zone: 0, num: 1, 3, 0),
                obs("A-2", zone: 0, num: 2, 6, 0),
                obs("B-1", zone: 1, num: 1, 3, 5),
            ],
            targetZoneIndex: 1, targetNumber: 2
        )
        #expect(result.stage == .gridGuidance)
        let target = try! #require(result.targetPosition)
        #expect(abs(target.x - 6) < 0.01)
        #expect(abs(target.y - 5) < 0.01)
        #expect(result.residualRMS < 0.01)
    }

    @Test func collinearIndexObservationsFallBackTo1D() {
        var estimator = GridEstimator()
        // 전부 A구역(구역 변화 없음) 3개 → 아핀 퇴화 → 번호축 1D
        let result = estimator.estimate(
            observations: [
                obs("A-1", zone: 0, num: 1, 3, 0),
                obs("A-2", zone: 0, num: 2, 6, 0),
                obs("A-3", zone: 0, num: 3, 9, 0),
            ],
            targetZoneIndex: 0, targetNumber: 5
        )
        #expect(result.stage == .axisGuidance(axis: .number))
        let target = try! #require(result.targetPosition)
        #expect(abs(target.x - 15) < 0.01)
    }

    // MARK: - 강등·복귀 (FR-012, 스네이크)

    @Test func snakeLayoutTriggersDegradationAndRecovers() {
        var estimator = GridEstimator()
        let clean = [
            obs("A-1", zone: 0, num: 1, 0, 0),
            obs("A-2", zone: 0, num: 2, 3, 0),
            obs("A-3", zone: 0, num: 3, 6, 0),
        ]
        // 정상 구간 (목표 A-4 — 레버 한도 내. 목표 9는 G1이 차단하므로 근거리 목표로 검증)
        var result = estimator.estimate(observations: clean, targetZoneIndex: 0, targetNumber: 4)
        #expect(result.stage == .axisGuidance(axis: .number))

        // 스네이크 접힘: A-4가 예측(9,0)과 크게 어긋난 (6,-14)에서 관측(다음 통로 역방향) → 강등
        let folded = clean + [obs("A-4", zone: 0, num: 4, 6, -14)]
        result = estimator.estimate(observations: folded, targetZoneIndex: 0, targetNumber: 4)
        #expect(result.stage == .degraded)
        #expect(result.targetPosition == nil)

        // 정합 관측 연속 2회 → 복귀
        result = estimator.estimate(observations: clean, targetZoneIndex: 0, targetNumber: 4)
        #expect(result.stage == .degraded)   // 1회째 — 아직 복귀 전
        result = estimator.estimate(observations: clean, targetZoneIndex: 0, targetNumber: 4)
        #expect(result.stage == .axisGuidance(axis: .number))   // 2회째 — 복귀
    }

    // MARK: - 신뢰도 + 인접 목격 (FR-013a)

    @Test func neighborSightingBoostsConfidence() {
        var estimator = GridEstimator()
        let observations = [
            obs("A-5", zone: 0, num: 5, 0, 0),
            obs("A-7", zone: 0, num: 7, 6, 0),
        ]
        let before = estimator.estimate(observations: observations, targetZoneIndex: 0, targetNumber: 3)
        estimator.markNeighborSighted()
        let after = estimator.estimate(observations: observations, targetZoneIndex: 0, targetNumber: 3)
        #expect(after.confidence > before.confidence)
    }

    @Test func confidenceGrowsWithObservations() {
        var estimator = GridEstimator()
        let five = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
            obs("B-2", zone: 1, num: 2, 6, 5),
            obs("C-1", zone: 2, num: 1, 3, 10),
        ]
        let result = estimator.estimate(observations: five, targetZoneIndex: 1, targetNumber: 3)
        #expect(result.confidence == .high)
    }

    @Test func fewObservationsCapConfidenceAtMedium() {
        // 260801 로그: 4점·잔차 0.22m로 high 표시됐지만 실오차 10.2m — 과신 상한 (FR-010)
        var estimator = GridEstimator()
        let four = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
            obs("B-2", zone: 1, num: 2, 6, 5),
        ]
        let result = estimator.estimate(observations: four, targetZoneIndex: 1, targetNumber: 3)
        #expect(result.stage == .gridGuidance)
        #expect(result.confidence == .medium)

        // 인접 목격 부스트는 격자 품질과 독립적인 근접 신호 — 상한 이후에도 유효 (FR-013a)
        estimator.markNeighborSighted()
        let boosted = estimator.estimate(observations: four, targetZoneIndex: 1, targetNumber: 3)
        #expect(boosted.confidence == .high)
    }

    // MARK: - 3중 가드 (설계 개정 v2)

    @Test func leverGuardBlocksFarExtrapolation() {
        // G1: B~C구역 관측으로 J구역(6+스텝 밖) 외삽 시도 → 화살표 대신 추가 관측 안내 (J21 세션 재현)
        var estimator = GridEstimator()
        let observations = [
            obs("B-3", zone: 1, num: 3, 0, 0),
            obs("C-3", zone: 2, num: 3, 14, 0),   // 피치 14 — G2 경계(15) 부동소수 회피
            obs("B-4", zone: 1, num: 4, 0, 10),
        ]
        let result = estimator.estimate(observations: observations, targetZoneIndex: 9, targetNumber: 3)
        #expect(result.stage == .needMoreObservation(missing: .zone))
        #expect((result.extrapolationLever ?? 0) > ParkingTuning.extrapolationLeverLimit)
    }

    @Test func leverGuardAllowsInterpolation() {
        // 관측 범위 안(또는 근접) 목표는 통과
        var estimator = GridEstimator()
        let observations = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let result = estimator.estimate(observations: observations, targetZoneIndex: 1, targetNumber: 2)
        #expect(result.stage == .gridGuidance)
        #expect((result.extrapolationLever ?? .infinity) <= ParkingTuning.extrapolationLeverLimit)
    }

    @Test func stepPriorRejectsAbsurdAxis() {
        // G2: 한 스텝 21.5m 축(J22 세션의 오염 축) 기각 — 다중 표지판 재앵커 왜곡 차단
        var estimator = GridEstimator()
        let observations = [
            obs("J-23", zone: 9, num: 23, 0, 0),
            obs("J-24", zone: 9, num: 24, 5.3, -20.8),   // |step| = 21.5m
        ]
        let result = estimator.estimate(observations: observations, targetZoneIndex: 9, targetNumber: 22)
        #expect(result.stage == .needMoreObservation(missing: .number))
    }

    @Test func stepPriorAllowsNormalPitch() {
        // 실측 정상 피치(10.5m)는 통과
        var estimator = GridEstimator()
        let observations = [
            obs("J-23", zone: 9, num: 23, 0, 0),
            obs("J-24", zone: 9, num: 24, 10.5, 0),
        ]
        let result = estimator.estimate(observations: observations, targetZoneIndex: 9, targetNumber: 22)
        #expect(result.stage == .axisGuidance(axis: .number))
    }

    @Test func residualNotInformativeAtExactFit() {
        // 아핀 3점은 정확결정계 — 잔차 0이어도 high 신뢰 조건에 기여하지 않음 (구조적 사망의 정직한 처리)
        var estimator = GridEstimator()
        let three = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let result = estimator.estimate(observations: three, targetZoneIndex: 1, targetNumber: 2)
        #expect(result.residualRMS < 1e-9)        // 항등 0 확인 (부동소수)
        #expect(result.confidence == .medium)     // 잔차 0이 high로 이어지지 않음
    }

    // MARK: - 관측 신선도 (260801: 드리프트 낡은 좌표 오염)

    @Test func staleObservationsAreExcludedFromFitting() {
        var estimator = GridEstimator()
        // 신선 2개(같은 번호·다른 구역) + 낡은 1개 — 낡은 관측이 제외되면 3점 아핀이 아니라 구역축 1D
        let mixed = [
            obs("D-3", zone: 3, num: 3, 22, 21),
            obs("E-3", zone: 4, num: 3, 11, 9),
            GridObservation(codeRaw: "F-4", zoneIndex: 5, numberValue: 4,
                            position: SIMD2(3.6, -5.7), ageSeconds: 40),   // 임계 30s 초과
        ]
        let result = estimator.estimate(observations: mixed, targetZoneIndex: 3, targetNumber: 5)
        #expect(result.observationCount == 2)
        // 같은 번호(3) 쌍 → 구역축 확보, 목표 번호(5)는 축 밖 → 번호축 추가 관측 안내
        #expect(result.stage == .needMoreObservation(missing: .number))
    }

    @Test func freshObservationsAreNotExcluded() {
        var estimator = GridEstimator()
        let fresh = [
            GridObservation(codeRaw: "A-1", zoneIndex: 0, numberValue: 1, position: SIMD2(3, 0), ageSeconds: 29),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let result = estimator.estimate(observations: fresh, targetZoneIndex: 1, targetNumber: 2)
        #expect(result.stage == .gridGuidance)
        #expect(result.observationCount == 3)
    }

    // MARK: - 도착 확정 (FR-013)

    @Test func arrivalRequiresConsecutiveSightingsWithInterval() {
        var tracker = ArrivalTracker()
        let t0 = Date()
        let first = tracker.registerTargetSighting(at: t0)                          // 1회 — 미확정
        let tooSoon = tracker.registerTargetSighting(at: t0.addingTimeInterval(0.3)) // 간격 미달 — 무시
        let second = tracker.registerTargetSighting(at: t0.addingTimeInterval(1.2))  // 2회 — 도착
        #expect(!first)
        #expect(!tooSoon)
        #expect(second)
    }

    @Test func arrivalResetClearsProgress() {
        var tracker = ArrivalTracker()
        let t0 = Date()
        _ = tracker.registerTargetSighting(at: t0)
        tracker.reset()
        let afterReset = tracker.registerTargetSighting(at: t0.addingTimeInterval(2))
        #expect(!afterReset)
    }
}
