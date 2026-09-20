import Testing
import Foundation
import simd
@testable import Navigation

/// 표지판 인스턴스 클러스터 (FR-107) — 제외 대신 분리 수용, 조합의 기하 일관성으로 선택
struct SignInstanceTests {

    // MARK: - 클러스터링

    @Test func nearbySightingsMergeIntoOneInstance() {
        var set = SignInstanceSet()
        set.add(position: SIMD2(0, 0), at: 0)
        set.add(position: SIMD2(1.5, 0), at: 1)     // 드리프트 재앵커 수준(<4m)
        #expect(set.instances.count == 1)
        #expect(!set.isMultiSign)
        // 표본 평균 — 최신값 덮어쓰기가 아니라 잡음을 줄인다
        #expect(abs(set.instances[0].position.x - 0.75) < 1e-9)
        #expect(set.instances[0].samples == 2)
    }

    @Test func distantSightingsBecomeSeparateInstances() {
        var set = SignInstanceSet()
        set.add(position: SIMD2(0, 0), at: 0)
        set.add(position: SIMD2(11, 0), at: 1)      // 복수 표지판 간격(260911 실측 7~13m)
        #expect(set.instances.count == 2)
        #expect(set.isMultiSign == false)           // 표본 1개짜리뿐이라 아직 채택 안 됨
        set.add(position: SIMD2(11.2, 0), at: 2)
        set.add(position: SIMD2(0.1, 0), at: 3)
        #expect(set.accepted.count == 2)
        #expect(set.isMultiSign)
    }

    @Test func singleInstanceSurvivesWithOneSample() {
        // 표본 2개 규칙은 경쟁 인스턴스가 있을 때만 — 위치를 한 번만 확보한 정상 코드를 버리면
        // raycast 실패가 잦은 주차장에서 v2보다 관측이 줄어든다(260710 세션 붕괴)
        var set = SignInstanceSet()
        set.add(position: SIMD2(3, 0), at: 0)
        #expect(set.accepted.count == 1)
    }

    @Test func mostRecentPositionTracksLastSighting() {
        var set = SignInstanceSet()
        set.add(position: SIMD2(0, 0), at: 0)
        set.add(position: SIMD2(20, 0), at: 5)
        let recent = try? #require(set.mostRecentPosition)
        #expect(recent?.x == 20)
    }

    // MARK: - 조합 선택 (평행 2열 혼합 방지)

    /// 실측 구조 재현: 11.5m 간격 평행 2열. 코드마다 독립적으로 최근 인스턴스를 고르면
    /// 서로 다른 열이 섞여도 잔차가 0으로 나오고 목표가 13.8m 어긋난다(PR#58 리뷰).
    @Test func selectionPrefersGeometricallyConsistentRow() {
        func instance(_ x: Double, _ y: Double, samples: Int = 2, at time: Double = 0) -> SignInstance {
            var made = SignInstance(position: SIMD2(x, y), at: time)
            for step in 1..<samples { made = merged(made, at: time + Double(step)) }
            return made
        }
        // A열 y=0, B열 y=11.5. 각 코드가 두 열 모두에 표지판을 가진다
        let candidates = [
            GridEstimator.GridCandidate(codeRaw: "A-1", zoneIndex: 0, numberValue: 1,
                                        instances: [instance(0, 0), instance(0, 11.5, at: 10)]),
            GridEstimator.GridCandidate(codeRaw: "A-2", zoneIndex: 0, numberValue: 2,
                                        instances: [instance(5, 0), instance(5, 11.5, at: 10)]),
            GridEstimator.GridCandidate(codeRaw: "A-3", zoneIndex: 0, numberValue: 3,
                                        instances: [instance(10, 0, at: 12), instance(10, 11.5)]),
        ]
        let chosen = GridEstimator.selectInstances(from: candidates, nowSeconds: 20)
        #expect(chosen.count == 3)
        // 같은 열에서 골라야 한다 — y가 모두 같은 값
        let ys = Set(chosen.map { ($0.position.y * 10).rounded() / 10 })
        #expect(ys.count == 1, "열이 섞였다: \(chosen.map(\.position))")
    }

    @Test func selectionIsDeterministicRegardlessOfInputOrder() {
        let a = GridEstimator.GridCandidate(codeRaw: "A-1", zoneIndex: 0, numberValue: 1,
                                            instances: [SignInstance(position: SIMD2(0, 0), at: 0)])
        let b = GridEstimator.GridCandidate(codeRaw: "A-2", zoneIndex: 0, numberValue: 2,
                                            instances: [SignInstance(position: SIMD2(5, 0), at: 1)])
        let forward = GridEstimator.selectInstances(from: [a, b], nowSeconds: 2)
        let reversed = GridEstimator.selectInstances(from: [b, a], nowSeconds: 2)
        #expect(forward.map(\.codeRaw) == reversed.map(\.codeRaw))
    }

    @Test func multiSignLotRestoresAxisThatV2Excluded() {
        // 260919 구조: '3'행 코드가 복수 표지판이라 v2에서 전멸 → 번호축 불성립.
        // 인스턴스로 나누면 축이 다시 선다
        var estimator = GridEstimator()
        func twin(_ code: String, zone: Int, num: Int, _ x: Double, _ y: Double) -> GridEstimator.GridCandidate {
            var near = SignInstance(position: SIMD2(x, y), at: 0)
            near = merged(near, at: 1)
            var far = SignInstance(position: SIMD2(x, y + 11), at: 2)
            far = merged(far, at: 3)
            return .init(codeRaw: code, zoneIndex: zone, numberValue: num, instances: [near, far])
        }
        let candidates = [
            twin("F-3", zone: 5, num: 3, 0, 0),
            twin("H-3", zone: 7, num: 3, 16.5, 0),
            GridEstimator.GridCandidate(codeRaw: "F-4", zoneIndex: 5, numberValue: 4,
                                        instances: [SignInstance(position: SIMD2(0, 4.8), at: 4)]),
        ]
        let estimate = estimator.estimate(candidates: candidates, targetZoneIndex: 9,
                                          targetNumber: 5, nowSeconds: 5)
        #expect(estimate.stage == .gridGuidance)
        #expect(estimate.targetPosition != nil)
    }

    /// 표본 수를 늘리기 위한 헬퍼 — 같은 위치를 다시 관측한 것으로 본다
    private func merged(_ instance: SignInstance, at time: Double) -> SignInstance {
        var set = SignInstanceSet()
        set.add(position: instance.position, at: instance.lastSeen)
        for _ in 0..<instance.samples { set.add(position: instance.position, at: time) }
        return set.instances[0]
    }
}
