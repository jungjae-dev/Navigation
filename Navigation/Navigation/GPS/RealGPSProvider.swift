import CoreLocation
import Combine

/// 실제 GPS Provider
/// - locationPublisher: 위치·엔진 통합 스트림
///   - GPS 수신 (accuracy <= 200): CLLocation 그대로 발행
///   - GPS 손실: horizontalAccuracy=300 CLLocation 발행 (앱 합성 손실 신호)
/// - GPS 손실 감지: 마지막 수신 후 1.1s 경과 시 손실 신호 발행 (0.5s 폴링)
/// - iPhone accuracy=-1 은 타이머 리셋에는 포함되나 엔진에 발행하지 않음
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
            .sink { [weak self] location in
                guard let self else { return }
                // accuracy 무관하게 타이머 리셋 — iPhone이 -1을 보내도 GPS가 살아있음을 의미
                lastGPSReceivedTime = Date()
                lastInvalidGPSTime = .distantPast
                if location.isValid {
                    handleLocationUpdate(location)
                }
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

        // lastLocation 값을 최대한 보존 — 좌표·속도·방향은 마지막 유효값 유지, horizontalAccuracy만 교체
        let lossLocation = CLLocation(
            coordinate: lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: lastLocation?.altitude ?? 0,
            horizontalAccuracy: CLLocation.gpsLossAccuracy,
            verticalAccuracy: lastLocation?.verticalAccuracy ?? -1,
            course: lastLocation?.course ?? -1,
            speed: lastLocation?.speed ?? 0,
            timestamp: now
        )
        locationSubject.send(lossLocation)
    }
}
