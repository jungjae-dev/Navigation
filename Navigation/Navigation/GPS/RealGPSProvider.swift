import CoreLocation
import Combine

/// 실제 GPS Provider
/// - LocationService.rawLocationPublisher를 구독해 GPSData로 변환
/// - 1초 틱 보장: GPS 미수신 시 타이머가 isValid=false GPSData 발행
/// - 정확도 필터: 첫 정확한 좌표 받기 전엔 부정확한 좌표도 통과 (초기 표시 위해)
final class RealGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsSubject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let gpsSubject = PassthroughSubject<GPSData, Never>()
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    private var tickTimer: Timer?
    private let tickInterval: TimeInterval = 1.0

    private var lastLocation: CLLocation?
    private var lastHeading: CLLocationDirection = 0
    private var lastGPSReceivedTime: Date = .distantPast

    /// 정확한 좌표(≤ 100m) 수신 후엔 부정확 좌표 차단 (스파이크 방지)
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

        locationService.headingPublisher
            .compactMap { $0 }
            .sink { [weak self] heading in
                self?.lastHeading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            }
            .store(in: &cancellables)

        // 1초 틱 타이머 시작
        startTickTimer()
    }

    func stop() {
        cancellables.removeAll()
        stopTickTimer()
        lastLocation = nil
        hasReceivedAccurateLocation = false
    }

    // MARK: - GPS 수신 처리

    private func handleLocationUpdate(_ location: CLLocation) {
        lastLocation = location
        lastGPSReceivedTime = Date()

        // heading: CLLocation.course가 유효하면 사용, 아니면 compass heading
        let heading = location.course >= 0 ? location.course : lastHeading

        let gpsData = GPSData(
            coordinate: location.coordinate,
            heading: heading,
            speed: max(0, location.speed),
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            isValid: true
        )

        locationSubject.send(location)
        gpsSubject.send(gpsData)

        // GPS 수신했으므로 타이머 리셋
        resetTickTimer()
    }

    // MARK: - 1초 틱 타이머 (GPS 미수신 대응)

    private func startTickTimer() {
        stopTickTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.handleTickTimeout()
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func resetTickTimer() {
        startTickTimer()
    }

    /// GPS가 1초 이상 안 오면 invalid GPSData 발행
    private func handleTickTimeout() {
        let gpsData = GPSData(
            coordinate: lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            heading: lastHeading,
            speed: lastLocation?.speed ?? 0,
            accuracy: lastLocation?.horizontalAccuracy ?? -1,
            timestamp: Date(),
            isValid: false
        )

        gpsSubject.send(gpsData)
    }
}
