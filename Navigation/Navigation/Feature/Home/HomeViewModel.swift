import Foundation
import Combine
import CoreLocation

final class HomeViewModel {

    // MARK: - Publishers

    let authStatus: CurrentValueSubject<LocationAuthStatus, Never>
    let currentLocation: CurrentValueSubject<CLLocation?, Never>
    let favorites = CurrentValueSubject<[FavoritePlace], Never>([])
    let recentSearches = CurrentValueSubject<[SearchHistory], Never>([])

    // MARK: - Private

    private let locationService: LocationService
    private let dataService: DataService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(locationService: LocationService, dataService: DataService = .shared) {
        self.locationService = locationService
        self.dataService = dataService
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

    // MARK: - Data Loading

    func loadHomeData() {
        favorites.send(dataService.fetchFavorites())
        recentSearches.send(dataService.fetchRecentSearches(limit: 10))
    }

    func deleteFavorite(_ place: FavoritePlace) {
        dataService.deleteFavorite(place)
        loadHomeData()
    }

    func deleteSearchHistory(_ item: SearchHistory) {
        dataService.deleteSearchHistory(item)
        loadHomeData()
    }
}
