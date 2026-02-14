import Foundation
import Combine
import CoreLocation

final class HomeViewModel {

    // MARK: - Publishers

    let authStatus: CurrentValueSubject<LocationAuthStatus, Never>
    let currentLocation: CurrentValueSubject<CLLocation?, Never>

    // MARK: - Private

    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(locationService: LocationService) {
        self.locationService = locationService
        self.authStatus = locationService.authStatusPublisher
        self.currentLocation = locationService.locationPublisher
    }

    // MARK: - Actions

    func requestLocationPermission() {
        locationService.requestAuthorization()
    }

    func startLocationUpdates() {
        locationService.startUpdating()
    }

    func stopLocationUpdates() {
        locationService.stopUpdating()
    }
}
