import Foundation
import simd

/// 같은 코드 문자열이 서로 다른 물리 위치에 붙어 있을 때의 **개별 표지판**(FR-107).
///
/// 260911·260919 주차장은 같은 번호가 7~13m 떨어진 복수 기둥에 반복 표기돼 있었다.
/// v2는 이런 코드를 통째로 격자에서 제외했고, 그 결과 260919에서는 '3'행이 전멸해
/// 번호축이 성립하지 못했다(화살표 0%). v3는 제외 대신 위치 클러스터로 분리해 수용한다.
struct SignInstance: Equatable, Sendable {
    /// 클러스터 대표 좌표(xz) — 표본 평균
    private(set) var position: SIMD2<Double>
    /// 이 클러스터에 모인 관측 수 — 1개짜리 유령 군집 배제에 사용
    private(set) var samples: Int
    /// 마지막 관측 시각(세션 기준 초)
    private(set) var lastSeen: Double

    init(position: SIMD2<Double>, at time: Double) {
        self.position = position
        self.samples = 1
        self.lastSeen = time
    }

    fileprivate mutating func merge(position newPosition: SIMD2<Double>, at time: Double) {
        // 표본 평균 — 한 표지판을 여러 번 본 관측 잡음을 줄인다(최신값 덮어쓰기는 드리프트에 취약)
        let n = Double(samples)
        position = (position * n + newPosition) / (n + 1)
        samples += 1
        lastSeen = time
    }
}

/// 한 코드의 관측 좌표들을 표지판 인스턴스로 나눠 보관한다.
/// VM과 리플레이어가 같은 타입을 쓰게 해 패리티 계약(005 DR-003)이 코드 수준에서 보장되도록 한다.
struct SignInstanceSet: Equatable, Sendable {

    private(set) var instances: [SignInstance] = []

    /// 새 관측을 임계 안의 기존 인스턴스에 병합하거나 새 인스턴스로 추가한다.
    /// 임계는 드리프트 재앵커(1~3m)와 복수 표지판(7~13m)을 가르는 값(ParkingTuning.sameCodeJumpThreshold).
    mutating func add(position: SIMD2<Double>, at time: Double) {
        let threshold = Double(ParkingTuning.sameCodeJumpThreshold)
        if let index = instances.indices.min(by: {
            simd_distance(instances[$0].position, position) < simd_distance(instances[$1].position, position)
        }), simd_distance(instances[index].position, position) <= threshold {
            instances[index].merge(position: position, at: time)
        } else {
            instances.append(SignInstance(position: position, at: time))
        }
    }

    /// 격자에 쓸 수 있는 인스턴스.
    ///
    /// 표본 2개 미만 배제는 **경쟁 인스턴스가 있을 때만** 적용한다(FR-107). 그 규칙의 목적은
    /// 단발 관측으로 생긴 유령 군집이 잘못된 조합에 뽑히는 것을 막는 데 있지, 위치를 한 번만 확보한
    /// 정상 코드를 버리는 데 있지 않다 — 라이다 raycast 실패가 잦은 주차장에서는 그런 코드가 다수이며
    /// 일괄 배제하면 v2보다 오히려 관측이 줄어든다(260710 세션이 45.5%→0%로 붕괴).
    var accepted: [SignInstance] {
        guard instances.count > 1 else { return instances }
        return instances.filter { $0.samples >= ParkingTuning.instanceMinSamples }
    }

    /// 여러 인스턴스가 살아 있는가 = 다중 표지판 코드
    var isMultiSign: Bool { accepted.count > 1 }

    /// 층 확인·도착 판정용 대표 좌표 — 가장 최근에 본 인스턴스(격자 선택과는 무관)
    var mostRecentPosition: SIMD2<Double>? {
        instances.max(by: { $0.lastSeen < $1.lastSeen })?.position
    }
}
