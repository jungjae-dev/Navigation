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

    /// 격자 후보로 넘길 인스턴스 — **표본 수로 미리 거르지 않는다**(FR-107 개정).
    ///
    /// 표본 2개 미만 배제는 원래 유령 군집을 막으려던 규칙이었으나, 실측에서 정반대로 작동했다:
    /// H22 세션의 G22는 격자 예측과 0.5m인 **1표본 클러스터가 정답**이고, G21과 0.3m 떨어진
    /// (같은 자리에 다른 코드가 있을 수 없으므로 오인식인) 7표본 클러스터가 오답이었다.
    /// 표본 수 프리필터는 정답을 버리고 오답을 채택해 잔차를 0→4.21m로 키웠다(PR#60 리뷰).
    /// 표본 수는 버리는 기준이 아니라 **동점 조합을 가르는 신호**로만 쓴다(GridEstimator.selectInstances).
    var accepted: [SignInstance] { instances }

    /// 여러 인스턴스가 살아 있는가 = 다중 표지판 코드
    var isMultiSign: Bool { accepted.count > 1 }

    /// 층 확인·도착 판정용 대표 좌표 — 가장 최근에 본 인스턴스(격자 선택과는 무관)
    var mostRecentPosition: SIMD2<Double>? {
        instances.max(by: { $0.lastSeen < $1.lastSeen })?.position
    }
}
