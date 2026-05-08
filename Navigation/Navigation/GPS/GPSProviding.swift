import CoreLocation
import Combine

/// GPS 데이터를 1초마다 발행하는 프로토콜
/// 엔진은 이 프로토콜만 의존하며, 소스(Real/File)를 알 필요 없음
/// - GPS 손실 신호: horizontalAccuracy < 0 인 CLLocation (Apple 컨벤션)
/// - GPS 유효 판정: horizontalAccuracy >= 0
/// - 맵매칭 적합 판정: 0 <= horizontalAccuracy <= 100
protocol GPSProviding: AnyObject {
    /// 위치 스트림 — 표시·엔진 통합. GPS 손실 시 horizontalAccuracy=-1 CLLocation 발행.
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }

    func start()
    func stop()
}
