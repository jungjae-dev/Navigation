import Combine

/// GPS 데이터를 1초마다 발행하는 프로토콜
/// 엔진은 이 프로토콜만 의존하며, 소스(Real/Simul/File)를 알 필요 없음
protocol GPSProviding: AnyObject {
    var gpsPublisher: AnyPublisher<GPSData, Never> { get }
    func start()
    func stop()
}
