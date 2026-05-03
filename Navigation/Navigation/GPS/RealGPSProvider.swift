import CoreLocation
import Combine

/// 실제 GPS Provider
/// - LocationService.rawLocationPublisher를 구독해 GPSData로 변환
/// - 1초 틱 보장: GPS 미수신 시 타이머가 isValid=false GPSData 발행
/// - 정확도 필터: 첫 정확한 좌표 받기 전엔 부정확한 좌표도 통과 (초기 표시 위해)
/// - heading: 폰 compass 방향은 사용하지 않음. GPS course 값만 사용.
///   course 무효(-1)이면 마지막 유효 course 유지(정지 구간 대응). GPS 미수신 시 -1.
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
    /// 마지막으로 유효했던 GPS course. 정지·저속 구간에서 직전 진행방향 유지용.
    /// GPS 미수신(tickTimeout) 시엔 -1 (isValid=false 라 다운스트림에서 무시됨).
    private var lastValidCourse: CLLocationDirection = -1
    private var lastGPSReceivedTime: Date = .distantPast

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

        // compass(headingPublisher) 구독 없음 — 폰 방향은 맵매칭에 사용하지 않음

        startTickTimer()
    }

    func stop() {
        cancellables.removeAll()
        stopTickTimer()
        lastLocation = nil
        lastValidCourse = -1
        hasReceivedAccurateLocation = false
    }

    // MARK: - GPS 수신 처리

    private func handleLocationUpdate(_ location: CLLocation) {
        lastLocation = location
        lastGPSReceivedTime = Date()

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

    /// GPS 가 1초 이상 안 오면 invalid GPSData 발행
    /// heading = -1: isValid=false 이므로 다운스트림(맵매칭)에서 무시됨
    private func handleTickTimeout() {
        let gpsData = GPSData(
            coordinate: lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            heading: -1,
            speed: lastLocation.map { max(0, $0.speed) } ?? 0,
            accuracy: lastLocation?.horizontalAccuracy ?? -1,
            timestamp: Date(),
            isValid: false
        )

        gpsSubject.send(gpsData)
    }
}
