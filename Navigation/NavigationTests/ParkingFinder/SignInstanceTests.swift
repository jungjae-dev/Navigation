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
        // 표본 수로 미리 버리지 않는다 — 1표본 클러스터가 정답인 사례가 실측에 있다(H22 G22)
        #expect(set.accepted.count == 2)
        #expect(set.isMultiSign)
    }

    @Test func singleSampleInstanceIsKeptAsCandidate() {
        // 표본 수는 버리는 기준이 아니라 동점 신호 — 프리필터는 260710을 45.5%→0%로,
        // H22를 49.1%→29.8%로 떨어뜨렸다(정답 클러스터를 버림)
        var set = SignInstanceSet()
        set.add(position: SIMD2(3, 0), at: 0)
        #expect(set.accepted.count == 1)
    }

    @Test func tieBreakPrefersLargerSpanThenSamples() {
        // 정확결정계(잔차 전부 0)에서 무엇이 조합을 고르는지 고정한다 —
        // 명시하지 않으면 부등호 방향만으로 가동률이 ±13~20pt 흔들린다(PR#60 리뷰)
        func instance(_ x: Double, _ y: Double, samples: Int, at time: Double) -> SignInstance {
            var set = SignInstanceSet()
            for step in 0..<samples { set.add(position: SIMD2(x, y), at: time + Double(step)) }
            return set.instances[0]
        }
        let candidates = [
            GridEstimator.GridCandidate(codeRaw: "A-1", zoneIndex: 0, numberValue: 1,
                                        instances: [instance(0, 0, samples: 1, at: 0)]),
            // 같은 잔차(2점은 항상 잔차 0)인 두 후보: 먼 쪽이 스팬을 키운다
            GridEstimator.GridCandidate(codeRaw: "A-2", zoneIndex: 0, numberValue: 2,
                                        instances: [instance(5, 0, samples: 3, at: 1),
                                                    instance(30, 0, samples: 1, at: 2)]),
        ]
        let chosen = GridEstimator.selectInstances(from: candidates, nowSeconds: 5)
        #expect(chosen.count == 2)
        #expect(chosen.contains { $0.position.x == 30 }, "스팬이 큰 조합을 골라야 한다")
    }

    @Test func deviceProximityBreaksRemainingTies() {
        // 스팬·표본까지 같으면 기기에 가까운 조합 (FR-107 동점 규칙 ⑤)
        func single(_ x: Double, _ y: Double) -> SignInstance { SignInstance(position: SIMD2(x, y), at: 0) }
        let candidates = [
            GridEstimator.GridCandidate(codeRaw: "A-1", zoneIndex: 0, numberValue: 1, instances: [single(0, 0)]),
            GridEstimator.GridCandidate(codeRaw: "A-2", zoneIndex: 0, numberValue: 2,
                                        instances: [single(10, 0), single(-10, 0)]),
        ]
        let nearPositive = GridEstimator.selectInstances(from: candidates, nowSeconds: 1,
                                                        devicePosition: SIMD2(12, 0))
        let nearNegative = GridEstimator.selectInstances(from: candidates, nowSeconds: 1,
                                                        devicePosition: SIMD2(-12, 0))
        #expect(nearPositive.contains { $0.position.x == 10 })
        #expect(nearNegative.contains { $0.position.x == -10 })
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
                                          targetNumber: 5, nowSeconds: 5, devicePosition: nil)
        #expect(estimate.stage == .gridGuidance)
        #expect(estimate.targetPosition != nil)
    }

    /// 같은 위치를 한 번 더 관측한 인스턴스를 만든다(표본 +1) — 이름대로 "한 번 병합"
    private func merged(_ instance: SignInstance, at time: Double) -> SignInstance {
        var set = SignInstanceSet()
        for _ in 0..<instance.samples { set.add(position: instance.position, at: instance.lastSeen) }
        set.add(position: instance.position, at: time)
        return set.instances[0]
    }
}
