import Foundation
import SwiftData
import MapKit
import CoreLocation

final class DataService {

    static let shared = DataService()

    // MARK: - Private

    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Configuration

    func configure(with container: ModelContainer) {
        modelContext = ModelContext(container)
    }

    // MARK: - Search History

    func saveSearchHistory(query: String, mapItem: MKMapItem) {
        guard let context = modelContext else { return }

        let name = mapItem.name ?? query
        let address = mapItem.address?.shortAddress ?? mapItem.address?.fullAddress ?? ""
        let coordinate = mapItem.location.coordinate

        // Check for duplicate (same coordinate within last hour)
        let recent = fetchRecentSearches(limit: 1)
        if let last = recent.first,
           last.placeName == name,
           abs(last.searchedAt.timeIntervalSinceNow) < 60 {
            // Skip duplicate within 1 minute
            return
        }

        let history = SearchHistory(
            query: query,
            placeName: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        context.insert(history)
        save()
    }

    func fetchRecentSearches(limit: Int = 20) -> [SearchHistory] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )

        do {
            let all = try context.fetch(descriptor)
            return Array(all.prefix(limit))
        } catch {
            print("[DataService] fetchRecentSearches error: \(error)")
            return []
        }
    }

    func clearAllSearchHistory() {
        guard let context = modelContext else { return }

        do {
            try context.delete(model: SearchHistory.self)
            save()
        } catch {
            print("[DataService] clearAllSearchHistory error: \(error)")
        }
    }

    func deleteSearchHistory(_ item: SearchHistory) {
        guard let context = modelContext else { return }
        context.delete(item)
        save()
    }

    // MARK: - Favorites

    func saveFavorite(name: String, mapItem: MKMapItem, category: String = "custom") {
        guard let context = modelContext else { return }

        let address = mapItem.address?.shortAddress ?? mapItem.address?.fullAddress ?? ""
        let coordinate = mapItem.location.coordinate

        let favorite = FavoritePlace(
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            category: category
        )

        context.insert(favorite)
        save()
    }

    func saveFavoriteFromCoordinate(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        category: String = "custom"
    ) {
        guard let context = modelContext else { return }

        let favorite = FavoritePlace(
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            category: category
        )

        context.insert(favorite)
        save()
    }

    func fetchFavorites() -> [FavoritePlace] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<FavoritePlace>(
            sortBy: [
                SortDescriptor(\.lastUsedAt, order: .reverse),
            ]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("[DataService] fetchFavorites error: \(error)")
            return []
        }
    }

    func deleteFavorite(_ place: FavoritePlace) {
        guard let context = modelContext else { return }
        context.delete(place)
        save()
    }

    func updateFavoriteUsedAt(_ place: FavoritePlace) {
        place.lastUsedAt = Date()
        save()
    }

    func isFavorite(latitude: Double, longitude: Double) -> Bool {
        let favorites = fetchFavorites()
        let threshold = 0.0001 // ~11m

        return favorites.contains { fav in
            abs(fav.latitude - latitude) < threshold &&
            abs(fav.longitude - longitude) < threshold
        }
    }

    func findFavorite(latitude: Double, longitude: Double) -> FavoritePlace? {
        let favorites = fetchFavorites()
        let threshold = 0.0001

        return favorites.first { fav in
            abs(fav.latitude - latitude) < threshold &&
            abs(fav.longitude - longitude) < threshold
        }
    }

    // MARK: - Private

    private func save() {
        guard let context = modelContext else { return }
        do {
            try context.save()
        } catch {
            print("[DataService] save error: \(error)")
        }
    }
}
