import CoreLocation
import Combine

/// 실제 GPS Provider
/// - locationSubject: accuracy >= 0 (기본화면 표시용)
/// - gpsSubject: accuracy 0~100m (주행 맵매칭용)
/// - GPS 손실 감지: 마지막 수신 후 1.1s 경과 시 isValid=false 발행 (0.5s 폴링)
/// - 연속 invalid: 0.9s 간격 rate limit
final class RealGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsSubject.eraseToAnyPublisher()
    }

    // MARK: - Configuration

    private let timerInterval: TimeInterval = 0.5
    private let gpsLossThreshold: TimeInterval = 1.1
    private let invalidGPSInterval: TimeInterval = 0.9

    // MARK: - Private

    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let gpsSubject = PassthroughSubject<GPSData, Never>()
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    private var tickTimer: Timer?

    private var lastLocation: CLLocation?
    private var lastValidCourse: CLLocationDirection = -1
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
        lastValidCourse = -1
        lastGPSReceivedTime = .distantPast
        lastInvalidGPSTime = .distantPast
    }

    // MARK: - GPS 수신 처리

    private func handleLocationUpdate(_ location: CLLocation) {
        // 기본화면 표시용 — accuracy >= 0 이면 모두 전송
        locationSubject.send(location)

        // 주행 맵매칭용 — accuracy 100m 이내만 처리
        guard location.isValidForNavigation else { return }

        lastLocation = location
        lastGPSReceivedTime = Date()
        lastInvalidGPSTime = .distantPast

        if location.hasValidCourse {
            lastValidCourse = location.course
        }

        gpsSubject.send(GPSData(
            coordinate: location.coordinate,
            heading: lastValidCourse,
            speed: max(0, location.speed),
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            isValid: true
        ))
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

        gpsSubject.send(GPSData(
            coordinate: lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            heading: -1,
            speed: lastLocation.map { max(0, $0.speed) } ?? 0,
            accuracy: lastLocation?.horizontalAccuracy ?? -1,
            timestamp: now,
            isValid: false
        ))
    }
}
