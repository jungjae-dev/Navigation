import UIKit
import CarPlay
import MapKit
import Combine
import CoreLocation

/// Handles favorite and recent destinations for CarPlay
final class CarPlayFavoritesHandler {

    // MARK: - Callbacks

    var onDestinationSelected: ((MKMapItem) -> Void)?

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
        let mapItem = MKMapItem(
            location: CLLocation(latitude: favorite.latitude, longitude: favorite.longitude),
            address: nil
        )
        mapItem.name = favorite.name
        dataService.updateFavoriteUsedAt(favorite)
        onDestinationSelected?(mapItem)
    }

    private func handleRecentSelected(_ history: SearchHistory) {
        let mapItem = MKMapItem(
            location: CLLocation(latitude: history.latitude, longitude: history.longitude),
            address: nil
        )
        mapItem.name = history.placeName
        onDestinationSelected?(mapItem)
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
