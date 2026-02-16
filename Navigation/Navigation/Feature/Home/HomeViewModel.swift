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

    func editFavorite(_ place: FavoritePlace, name: String, category: String) {
        place.name = name
        place.category = category
        dataService.updateFavorite(place)
        loadHomeData()
    }

    func setQuickFavorite(type: String, coordinate: CLLocationCoordinate2D, address: String) {
        // Check if quick favorite (home/work) already exists
        let existing = dataService.fetchFavorites().first { $0.category == type }
        if let existing {
            existing.latitude = coordinate.latitude
            existing.longitude = coordinate.longitude
            existing.address = address
            dataService.updateFavorite(existing)
        } else {
            let name = type == "home" ? "집" : "회사"
            dataService.saveFavoriteFromCoordinate(
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                category: type
            )
        }
        loadHomeData()
    }
}
