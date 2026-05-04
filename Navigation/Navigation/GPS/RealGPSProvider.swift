import CoreLocation
import Combine

/// 실제 GPS Provider
/// - LocationService.rawLocationPublisher를 구독해 GPSData로 변환
/// - GPS 손실 감지: 마지막 GPS 수신 후 1.1s 경과 시 isValid=false 발행 (0.5s 폴링)
/// - 연속 invalid: 0.9s 간격으로 rate limit
/// - heading: GPS course 값만 사용. course 무효(-1)이면 마지막 유효 course 유지.
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

    private var hasReceivedAccurateLocation = false
    private static let accuracyThreshold: CLLocationAccuracy = 100

    // MARK: - Init

    init(locationService: LocationService = .shared) {
        self.locationService = locationService
    }

    // MARK: - GPSProviding

    func start() {
        locationService.rawLocationPublisher
            .compactMap { $0 }
            .filter { [weak self] location in
                guard let self, location.horizontalAccuracy >= 0 else { return false }
                if location.horizontalAccuracy <= Self.accuracyThreshold {
                    hasReceivedAccurateLocation = true
                    return true
                }
                return !hasReceivedAccurateLocation
            }
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
        hasReceivedAccurateLocation = false
    }

    // MARK: - GPS 수신 처리

    private func handleLocationUpdate(_ location: CLLocation) {
        lastLocation = location
        lastGPSReceivedTime = Date()
        lastInvalidGPSTime = .distantPast  // GPS 복구 시 invalid 상태 초기화

        if location.course >= 0 {
            lastValidCourse = location.course
        }

        let gpsData = GPSData(
            coordinate: location.coordinate,
            heading: lastValidCourse,
            speed: max(0, location.speed),
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            isValid: true
        )

        locationSubject.send(location)
        gpsSubject.send(gpsData)
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

        // 마지막 GPS 수신 후 1.1s 미경과 → 아직 손실 아님
        guard now.timeIntervalSince(lastGPSReceivedTime) >= gpsLossThreshold else { return }

        // 직전 invalid 발행 후 0.9s 미경과 → rate limit
        guard now.timeIntervalSince(lastInvalidGPSTime) >= invalidGPSInterval else { return }

        lastInvalidGPSTime = now

        let gpsData = GPSData(
            coordinate: lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            heading: -1,
            speed: lastLocation.map { max(0, $0.speed) } ?? 0,
            accuracy: lastLocation?.horizontalAccuracy ?? -1,
            timestamp: now,
            isValid: false
        )

        gpsSubject.send(gpsData)
    }
}
