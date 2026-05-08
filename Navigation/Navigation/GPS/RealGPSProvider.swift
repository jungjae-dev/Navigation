import CoreLocation
import Combine

/// 실제 GPS Provider
/// - locationPublisher: 위치·엔진 통합 스트림
///   - GPS 수신: CLLocation 그대로 발행 (accuracy >= 0)
///   - GPS 손실: horizontalAccuracy=-1 CLLocation 발행 (Apple 컨벤션)
/// - GPS 손실 감지: 마지막 수신 후 1.1s 경과 시 손실 신호 발행 (0.5s 폴링)
/// - 연속 invalid: 0.9s 간격 rate limit
final class RealGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    // MARK: - Configuration

    private let timerInterval: TimeInterval = 0.5
    private let gpsLossThreshold: TimeInterval = 1.1
    private let invalidGPSInterval: TimeInterval = 0.9

    // MARK: - Private

    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    private var tickTimer: Timer?

    private var lastLocation: CLLocation?
    private var lastGPSReceivedTime: Date = .distantPast
    private var lastInvalidGPSTime: Date = .distantPast

    // MARK: - Init

    init(locationService: LocationService = .shared) {
        self.locationService = locationService
    }

    // MARK: - GPSProviding

    func start() {
        locationService.rawLocationPublisher
            .compactMap { $0 }
            .filter { $0.isValidForDisplay }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)

        startTickTimer()
    }

    func stop() {
        cancellables.removeAll()
        stopTickTimer()
        lastLocation = nil
        lastGPSReceivedTime = .distantPast
        lastInvalidGPSTime = .distantPast
    }

    // MARK: - GPS 수신 처리

    private func handleLocationUpdate(_ location: CLLocation) {
        lastLocation = location
        lastGPSReceivedTime = Date()
        lastInvalidGPSTime = .distantPast

        locationSubject.send(location)
    }

    // MARK: - GPS 손실 감지 타이머

    private func startTickTimer() {
        stopTickTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            self?.handleTickTimeout()
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func handleTickTimeout() {
        let now = Date()
        guard now.timeIntervalSince(lastGPSReceivedTime) >= gpsLossThreshold else { return }
        guard now.timeIntervalSince(lastInvalidGPSTime) >= invalidGPSInterval else { return }

        lastInvalidGPSTime = now

        // horizontalAccuracy = -1: Apple 컨벤션 상 무효 좌표 (GPS 손실 신호)
        let lossLocation = CLLocation(
            coordinate: lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: lastLocation?.altitude ?? 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            course: -1,
            speed: 0,
            timestamp: now
        )
        locationSubject.send(lossLocation)
    }
}
