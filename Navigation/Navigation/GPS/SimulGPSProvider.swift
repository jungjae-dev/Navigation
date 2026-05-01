import CoreLocation
import Combine

/// 가상 주행 GPS Provider
/// LocationSimulator를 사용하여 폴리라인 위를 자동 이동
final class SimulGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        simulator.simulatedLocationPublisher.eraseToAnyPublisher()
    }

    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsSubject.eraseToAnyPublisher()
    }

    // MARK: - Configuration

    private static let defaultSpeedMPS: Double = 13.9   // ~50 km/h
    private static let walkingSpeedMPS: Double = 1.4    // ~5 km/h

    // MARK: - Public Publishers (LocationSimulator 위임)

    var isPlayingPublisher: CurrentValueSubject<Bool, Never> {
        simulator.isPlayingPublisher
    }
    var progressPublisher: CurrentValueSubject<Double, Never> {
        simulator.progressPublisher
    }
    var speedMultiplierPublisher: CurrentValueSubject<Double, Never> {
        simulator.speedMultiplierPublisher
    }
    /// 시뮬레이션 위치 발행 (LocationService.override 등에 연결 가능)
    var simulatedLocationPublisher: PassthroughSubject<CLLocation, Never> {
        simulator.simulatedLocationPublisher
    }

    // MARK: - Private

    private let gpsSubject = PassthroughSubject<GPSData, Never>()
    private let simulator = LocationSimulator()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // LocationSimulator의 CLLocation → GPSData 변환
        simulator.simulatedLocationPublisher
            .sink { [weak self] location in
                self?.handleLocation(location)
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    /// 폴리라인 + 교통 모드로 가상 주행 데이터 생성
    func load(polyline: [CLLocationCoordinate2D], transportMode: TransportMode = .automobile) {
        let speed = transportMode == .walking
            ? Self.walkingSpeedMPS
            : Self.defaultSpeedMPS
        simulator.load(polyline: polyline, speedMPS: speed)
    }

    // MARK: - GPSProviding

    func start() {
        simulator.play()
    }

    func stop() {
        simulator.stop()
    }

    // MARK: - Playback Control (LocationSimulator 위임)

    func play() { simulator.play() }
    func pause() { simulator.pause() }
    func cycleSpeed() { simulator.cycleSpeed() }

    // MARK: - Private

    private func handleLocation(_ location: CLLocation) {
        let gpsData = GPSData(
            coordinate: location.coordinate,
            heading: location.course >= 0 ? location.course : 0,
            speed: max(0, location.speed),
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            isValid: true
        )
        gpsSubject.send(gpsData)
    }
}
