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

    let locationPublisher = CurrentValueSubject<CLLocation?, Never>(nil)
    let headingPublisher = CurrentValueSubject<CLHeading?, Never>(nil)
    let authStatusPublisher = CurrentValueSubject<LocationAuthStatus, Never>(.notDetermined)

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var isUpdating = false

    // MARK: - Init

    private override init() {
        super.init()
        locationManager.delegate = self
        authStatusPublisher.send(LocationAuthStatus(from: locationManager.authorizationStatus))
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
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter inaccurate locations
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100 else {
            return
        }

        MainActor.assumeIsolated {
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
        print("[LocationService] Error: \(error.localizedDescription)")
    }
}
