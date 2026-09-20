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
        // v3(FR-109): 목표(B구역)가 축 밖이어도 안내를 포기하지 않는다 —
        // 미지 구역축 오프셋은 대칭 불확실성이 되고 점추정은 번호축 위에 남는다
        let result = estimator.estimate(
            observations: [
                obs("A-5", zone: 0, num: 5, 0, 0),
                obs("A-7", zone: 0, num: 7, 6, 0),
            ],
            targetZoneIndex: 1, targetNumber: 3
        )
        #expect(result.stage == .axisGuidance(axis: .number))
        #expect(result.targetPosition != nil)
        #expect(result.uncertainty.unknownAxis == ParkingTuning.unknownZoneAxisPitchPrior)   // 1스텝 × 구역축 사전값
        #expect(result.confidencePercent < ParkingTuning.confidencePercentSolidThreshold)
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
        // v3: 3단계가 아니라 연속 백분율이 오른다 (FR-103)
        #expect(after.confidencePercent > before.confidencePercent)
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
        var fewer = GridEstimator()
        let three = fewer.estimate(observations: Array(five.prefix(3)), targetZoneIndex: 1, targetNumber: 3)
        // v3: 관측이 늘수록 백분율이 오른다. 절대 등급 대신 단조성으로 고정(임계 튜닝에 깨지지 않게)
        #expect(result.confidencePercent > three.confidencePercent)
        #expect(result.confidencePercent <= ParkingTuning.confidencePercentCap)
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
        #expect(result.confidencePercent < 70)   // 4점·잔차 0이어도 최상위 구간에 닿지 않는다

        // 인접 목격 부스트는 격자 품질과 독립적인 근접 신호 (FR-013a)
        estimator.markNeighborSighted()
        let boosted = estimator.estimate(observations: four, targetZoneIndex: 1, targetNumber: 3)
        #expect(boosted.confidencePercent > result.confidencePercent)
    }

    // MARK: - 3중 가드 (설계 개정 v2)

    @Test func expansionRecoversWhenNewPillarsAreObserved() {
        // FR-108 "새 관측이 들어오면 회복된다" — 최댓값 기반이면 오래된 관측 하나가 남는 한
        // 새 기둥을 아무리 비춰도 상한까지 래칫된다(PR#59 리뷰에서 확인된 결함)
        var estimator = GridEstimator()
        let stale = GridObservation(codeRaw: "A-1", zoneIndex: 0, numberValue: 1,
                                    position: SIMD2(3, 0), ageSeconds: 120)
        let before = estimator.estimate(
            observations: [stale, obs("A-2", zone: 0, num: 2, 6, 0), obs("B-1", zone: 1, num: 1, 3, 5)],
            targetZoneIndex: 1, targetNumber: 2
        )
        // 오래된 관측은 그대로 둔 채 새 기둥 두 개를 추가로 관측
        let after = estimator.estimate(
            observations: [stale, obs("A-2", zone: 0, num: 2, 6, 0), obs("B-1", zone: 1, num: 1, 3, 5),
                           obs("B-2", zone: 1, num: 2, 6, 5), obs("C-1", zone: 2, num: 1, 3, 10)],
            targetZoneIndex: 1, targetNumber: 2
        )
        #expect(after.uncertainty.expansion < before.uncertainty.expansion)
    }

    @Test func topTierRequiresNeighborSighting() {
        // FR-104 AND 게이트 — 관측 5개·잔차 양호만으로는 최상위 구간에 가지 못한다
        var estimator = GridEstimator()
        let five = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
            obs("B-2", zone: 1, num: 2, 6, 5),
            obs("C-1", zone: 2, num: 1, 3, 10),
        ]
        let withoutNeighbor = estimator.estimate(observations: five, targetZoneIndex: 1, targetNumber: 3)
        #expect(withoutNeighbor.confidencePercent < ParkingTuning.confidencePercentTopThreshold)

        estimator.markNeighborSighted()
        let withNeighbor = estimator.estimate(observations: five, targetZoneIndex: 1, targetNumber: 3)
        #expect(withNeighbor.confidencePercent >= ParkingTuning.confidencePercentTopThreshold)
    }

    @Test func unknownAxisUsesSessionMeasuredPitchWhenAvailable() {
        // FR-101: 2D로 번호축을 학습한 뒤 1D로 내려가면 정적 사전값(12m) 대신 학습한 피치를 쓴다
        var estimator = GridEstimator()
        _ = estimator.estimate(
            observations: [
                obs("A-1", zone: 0, num: 1, 3, 0),
                obs("A-2", zone: 0, num: 2, 6, 0),   // 번호 1스텝 = 3m
                obs("B-1", zone: 1, num: 1, 3, 5),
            ],
            targetZoneIndex: 1, targetNumber: 2
        )
        // 관측이 줄어 구역축 1D로 하강, 목표 번호는 축 밖
        let result = estimator.estimate(
            observations: [
                obs("A-1", zone: 0, num: 1, 3, 0),
                obs("B-1", zone: 1, num: 1, 3, 5),
            ],
            targetZoneIndex: 1, targetNumber: 2
        )
        #expect(abs(result.uncertainty.unknownAxis - 3.0) < 1e-9)   // 학습한 3m/스텝 × 1스텝
        #expect(result.uncertainty.unknownAxis < ParkingTuning.unknownNumberAxisPitchPrior)
    }

    @Test func farExtrapolationRaisesUncertaintyInsteadOfBlocking() {
        // v3(FR-101/105): 레버는 더 이상 차단 기준이 아니다 — 안내는 유지하되 불확실성이 커지고 백분율이 떨어진다.
        // J21(6스텝 외삽·잔차 0.1m) 부류에서 잔차만 보면 위험이 0.5m로 과소평가되므로
        // 스텝당 모델 오차가 누적되어야 한다
        var estimator = GridEstimator()
        let observations = [
            obs("B-3", zone: 1, num: 3, 0, 0),
            obs("C-3", zone: 2, num: 3, 14, 0),
            obs("B-4", zone: 1, num: 4, 0, 10),
        ]
        let far = estimator.estimate(observations: observations, targetZoneIndex: 9, targetNumber: 3)
        let near = estimator.estimate(observations: observations, targetZoneIndex: 2, targetNumber: 4)
        #expect(far.stage == .gridGuidance)
        #expect(far.targetPosition != nil)
        // 차단은 하지 않지만 레버가 크고, 실제 화살표 차단은 GuidanceGeometry의 스팬 상대 기준이 맡는다
        #expect((far.extrapolationLever ?? 0) > ParkingTuning.extrapolationLeverLimit)
        #expect((near.extrapolationLever ?? .infinity) < (far.extrapolationLever ?? 0))
    }

    @Test func interpolationKeepsUncertaintyLow() {
        var estimator = GridEstimator()
        let observations = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let result = estimator.estimate(observations: observations, targetZoneIndex: 1, targetNumber: 2)
        #expect(result.stage == .gridGuidance)
        #expect(result.uncertainty.radius < 1.0)   // 범위 내 보간 — 외삽 누적 없음
    }

    @Test func absurdStepIsBlockedButBoundaryIsPenalizedOnly() {
        // v3(FR-105): 위생 검사는 부조리(25m 초과)만 차단하고, 실측 경계(21.5m)는 감점으로 처리.
        // 정상 피치 16.9m를 기각하던 좁은 상한(15m)이 260919 가동률 0%의 원인 중 하나였다
        var estimator = GridEstimator()
        let absurd = estimator.estimate(
            observations: [
                obs("J-23", zone: 9, num: 23, 0, 0),
                obs("J-24", zone: 9, num: 24, 0, -30),   // |step| = 30m — 부조리
            ],
            targetZoneIndex: 9, targetNumber: 22
        )
        #expect(absurd.stage == .needMoreObservation(missing: .number))

        var estimator2 = GridEstimator()
        let boundary = estimator2.estimate(
            observations: [
                obs("J-23", zone: 9, num: 23, 0, 0),
                obs("J-24", zone: 9, num: 24, 5.3, -20.8),   // |step| = 21.5m — 감점 대상
            ],
            targetZoneIndex: 9, targetNumber: 22
        )
        #expect(boundary.stage == .axisGuidance(axis: .number))
        #expect(boundary.confidencePercent < ParkingTuning.confidencePercentSolidThreshold)

        var estimator3 = GridEstimator()
        let normalPitch = estimator3.estimate(
            observations: [
                obs("H-4", zone: 7, num: 4, 0, 0),
                obs("J-4", zone: 9, num: 4, 0, 33),   // 16.5m/스텝 — 260919 실측 정상 피치
            ],
            targetZoneIndex: 9, targetNumber: 4
        )
        #expect(normalPitch.stage == .axisGuidance(axis: .zone))   // 구 상한 15m에서는 기각되던 격자
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
        // FR-104①: 무정보 잔차는 가산이 아니라 상한 하향으로 처리 — 최상위 구간 진입 불가
        #expect(result.confidencePercent < 70)
    }

    // MARK: - 관측 노화 → 불확실성 팽창 (v3 FR-108, 구 신선도 제외의 대체)

    @Test func staleObservationsExpandUncertaintyInsteadOfBeingExcluded() {
        var estimator = GridEstimator()
        let fresh = [
            obs("A-1", zone: 0, num: 1, 3, 0),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let aged = [
            GridObservation(codeRaw: "A-1", zoneIndex: 0, numberValue: 1, position: SIMD2(3, 0), ageSeconds: 60),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let freshResult = estimator.estimate(observations: fresh, targetZoneIndex: 1, targetNumber: 2)
        var estimator2 = GridEstimator()
        let agedResult = estimator2.estimate(observations: aged, targetZoneIndex: 1, targetNumber: 2)

        // 제외되지 않는다 — 관측 수가 유지되고 점추정도 같다 (팽창은 점추정을 오염시키지 않는다)
        #expect(agedResult.observationCount == 3)
        #expect(agedResult.stage == .gridGuidance)
        #expect(agedResult.targetPosition == freshResult.targetPosition)
        // 대신 불확실성이 커지고 백분율이 낮아진다
        #expect(agedResult.uncertainty.expansion > freshResult.uncertainty.expansion)
        #expect(agedResult.confidencePercent < freshResult.confidencePercent)
    }

    @Test func expansionIsCapped() {
        var estimator = GridEstimator()
        let veryOld = [
            GridObservation(codeRaw: "A-1", zoneIndex: 0, numberValue: 1, position: SIMD2(3, 0), ageSeconds: 100_000),
            obs("A-2", zone: 0, num: 2, 6, 0),
            obs("B-1", zone: 1, num: 1, 3, 5),
        ]
        let result = estimator.estimate(observations: veryOld, targetZoneIndex: 1, targetNumber: 2)
        #expect(result.uncertainty.expansion == ParkingTuning.expansionMaxMeters)
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
