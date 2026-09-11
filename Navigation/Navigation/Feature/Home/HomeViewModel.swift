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
        // 홈 드로어는 앞쪽 5개만 보여주지만(HomeDrawerViewController), 즐겨찾기와
        // 마찬가지로 이 subject 자체는 전체(저장 상한까지)를 들고 있어야
        // 즐겨찾기·최근 목적지 전체 목록 화면이 같은 source를 그대로 재사용할 수 있음.
        recentSearches.send(dataService.fetchRecentSearches(limit: DataService.maxSearchHistoryCount))
    }

    func deleteFavorite(_ place: FavoritePlace) {
        dataService.deleteFavorite(place)
        loadHomeData()
    }

    func deleteFavorites(_ places: [FavoritePlace]) {
        guard !places.isEmpty else { return }
        for place in places {
            dataService.deleteFavorite(place)
        }
        loadHomeData()
    }

    func deleteSearchHistory(_ item: SearchHistory) {
        dataService.deleteSearchHistory(item)
        loadHomeData()
    }

    func deleteSearchHistories(_ items: [SearchHistory]) {
        guard !items.isEmpty else { return }
        for item in items {
            dataService.deleteSearchHistory(item)
        }
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
