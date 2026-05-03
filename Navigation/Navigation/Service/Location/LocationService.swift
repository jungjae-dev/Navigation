import CoreLocation
import Combine

enum LocationAuthStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways

    nonisolated init(from status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedWhenInUse: self = .authorizedWhenInUse
        case .authorizedAlways: self = .authorizedAlways
        @unknown default: self = .notDetermined
        }
    }

    var isAuthorized: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }
}

final class LocationService: NSObject {

    static let shared = LocationService()

    // MARK: - Publishers

    /// 활성 Provider의 위치 출력 (Real/File에 따라 자동 전환)
    /// - activeProvider 미설정 시: CLLocationManager 직접 출력 (backward compat)
    let locationPublisher = CurrentValueSubject<CLLocation?, Never>(nil)
    /// 정확도 필터를 거치지 않은 raw 위치 (RealGPSProvider 입력 + 초기 지도 이동용)
    let rawLocationPublisher = CurrentValueSubject<CLLocation?, Never>(nil)
    /// 활성 Provider의 GPSData 출력 (engine 입력 — activeProvider 설정 후 흐름)
    let gpsPublisher = PassthroughSubject<GPSData, Never>()
    let headingPublisher = CurrentValueSubject<CLHeading?, Never>(nil)
    let authStatusPublisher = CurrentValueSubject<LocationAuthStatus, Never>(.notDetermined)
    let locationErrorPublisher = PassthroughSubject<Error, Never>()

    // MARK: - Active Provider

    private(set) var activeProvider: GPSProviding?
    private var providerLocationCancellable: AnyCancellable?
    private var providerGPSCancellable: AnyCancellable?

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var isUpdating = false

    // MARK: - Init

    private override init() {
        super.init()
        locationManager.delegate = self
        authStatusPublisher.send(LocationAuthStatus(from: locationManager.authorizationStatus))
    }

    /// 정확한 위치 → raw → CLLocationManager 캐시 순 fallback
    var bestAvailableLocation: CLLocation? {
        locationPublisher.value ?? rawLocationPublisher.value ?? cachedLocation
    }

    /// CLLocationManager 마지막 캐시 (이전 세션 포함, 앱 시작 시드용)
    var cachedLocation: CLLocation? {
        locationManager.location
    }

    // MARK: - Public Methods

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        guard !isUpdating else { return }
        isUpdating = true

        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.activityType = .automotiveNavigation
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false

        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    func configureForNavigation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.activityType = .automotiveNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func configureForWalking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.activityType = .fitness
    }

    func configureForStandard() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.activityType = .automotiveNavigation
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Active Provider Management

    /// 활성 Provider 설정 — 이전 Provider는 stop 후 교체
    /// - Real/File 전환에 사용. 가상주행은 별도 흐름 (Phase B의 VirtualDriveDriver).
    func setProvider(_ provider: GPSProviding) {
        clearProvider()

        activeProvider = provider
        providerLocationCancellable = provider.locationPublisher
            .sink { [weak self] location in
                self?.locationPublisher.send(location)
            }
        providerGPSCancellable = provider.gpsPublisher
            .sink { [weak self] gps in
                self?.gpsPublisher.send(gps)
            }
        provider.start()
    }

    /// 활성 Provider 해제
    func clearProvider() {
        activeProvider?.stop()
        providerLocationCancellable?.cancel()
        providerGPSCancellable?.cancel()
        providerLocationCancellable = nil
        providerGPSCancellable = nil
        activeProvider = nil
    }

}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        MainActor.assumeIsolated {
            rawLocationPublisher.send(location)
        }

        // Filter inaccurate locations
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100 else {
            return
        }

        MainActor.assumeIsolated {
            // activeProvider가 설정된 경우 provider가 locationPublisher를 구동
            guard activeProvider == nil else { return }
            locationPublisher.send(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }

        MainActor.assumeIsolated {
            headingPublisher.send(newHeading)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = LocationAuthStatus(from: manager.authorizationStatus)
        MainActor.assumeIsolated {
            authStatusPublisher.send(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // CLError.locationUnknown is temporary, ignore it
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        MainActor.assumeIsolated {
            locationErrorPublisher.send(error)
        }
    }
}
