import UIKit
import CarPlay
import CoreLocation

/// Handles favorite and recent destinations for CarPlay
final class CarPlayFavoritesHandler {

    // MARK: - Callbacks

    var onDestinationSelected: ((Place) -> Void)?

    // MARK: - Dependencies

    private let dataService: DataService
    private let locationService: LocationService

    // MARK: - Init

    init(dataService: DataService = .shared, locationService: LocationService) {
        self.dataService = dataService
        self.locationService = locationService
    }

    // MARK: - Public

    /// Create a CPListTemplate showing favorite places
    func createFavoritesTemplate() -> CPListTemplate {
        let favorites = dataService.fetchFavorites()

        let items = favorites.prefix(12).map { favorite -> CPListItem in
            let item = CPListItem(
                text: favorite.name,
                detailText: favorite.address,
                image: categoryImage(for: favorite.category)
            )
            item.handler = { [weak self] _, completion in
                self?.handleFavoriteSelected(favorite)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items, header: "즐겨찾기", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "즐겨찾기", sections: [section])
        return template
    }

    /// Create a CPListTemplate showing recent search history
    func createRecentsTemplate() -> CPListTemplate {
        let recents = dataService.fetchRecentSearches(limit: 12)

        let items = recents.map { history -> CPListItem in
            let item = CPListItem(
                text: history.placeName,
                detailText: history.address,
                image: UIImage(systemName: "clock.arrow.circlepath")
            )
            item.handler = { [weak self] _, completion in
                self?.handleRecentSelected(history)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items, header: "최근 검색", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "최근 검색", sections: [section])
        return template
    }

    // MARK: - Private

    private func handleFavoriteSelected(_ favorite: FavoritePlace) {
        let place = Place(
            name: favorite.name,
            coordinate: CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude),
            address: favorite.address,
            phoneNumber: nil, url: nil, category: favorite.category, providerRawData: nil
        )
        dataService.updateFavoriteUsedAt(favorite)
        onDestinationSelected?(place)
    }

    private func handleRecentSelected(_ history: SearchHistory) {
        let place = Place(
            name: history.placeName,
            coordinate: CLLocationCoordinate2D(latitude: history.latitude, longitude: history.longitude),
            address: history.address,
            phoneNumber: nil, url: nil, category: nil, providerRawData: nil
        )
        onDestinationSelected?(place)
    }

    private func categoryImage(for category: String) -> UIImage? {
        switch category {
        case "home":
            return UIImage(systemName: "house.fill")
        case "work":
            return UIImage(systemName: "building.2.fill")
        default:
            return UIImage(systemName: "star.fill")
        }
    }
}
