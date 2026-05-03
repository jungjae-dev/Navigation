import CoreLocation
import Combine

/// GPS 데이터를 1초마다 발행하는 프로토콜
/// 엔진은 이 프로토콜만 의존하며, 소스(Real/File)를 알 필요 없음
protocol GPSProviding: AnyObject {
    /// GPS 좌표 — MapView, GPXRecorder 등 위치 표시 용도
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }

    /// 엔진 입력 — 1초 틱 보장 + isValid 플래그 포함
    var gpsPublisher: AnyPublisher<GPSData, Never> { get }

    func start()
    func stop()
}
