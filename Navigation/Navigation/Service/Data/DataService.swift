import Foundation
import SwiftData
import CoreLocation
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

    func saveSearchHistory(query: String, place: Place) {
        guard let context = modelContext else { return }

        let name = place.name ?? query
        let address = place.address ?? ""
        let coordinate = place.coordinate

        // 같은 장소가 이미 있으면 타임스탬프만 갱신 (upsert → 목록 맨 위로 이동)
        // 동일 판정: 이름 일치 + 좌표 10m 이내 (같은 건물 내 다른 업체 구분)
        let all = fetchRecentSearches(limit: 1000)
        let threshold = 0.0001   // ~10m
        if let existing = all.first(where: {
            $0.placeName == name &&
            abs($0.latitude - coordinate.latitude) < threshold &&
            abs($0.longitude - coordinate.longitude) < threshold
        }) {
            existing.searchedAt = Date()
            existing.query = query
            save()
            return
        }

        context.insert(SearchHistory(
            query: query,
            placeName: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
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

    func saveFavorite(name: String, place: Place, category: String = "custom") {
        guard let context = modelContext else { return }

        let address = place.address ?? ""
        let coordinate = place.coordinate

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

    func updateFavorite(_ place: FavoritePlace) {
        save()
    }

    func reorderFavorites(_ places: [FavoritePlace]) {
        for (index, place) in places.enumerated() {
            place.sortOrder = index
        }
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

    // MARK: - Recordings

    func saveRecording(
        fileName: String,
        filePath: String,
        duration: TimeInterval,
        distance: Double,
        pointCount: Int,
        fileSize: Int64,
        recordingMode: String = "real",
        originName: String? = nil,
        destinationName: String? = nil
    ) {
        guard let context = modelContext else { return }

        let recording = Recording(
            fileName: fileName,
            filePath: filePath,
            duration: duration,
            distance: distance,
            pointCount: pointCount,
            fileSize: fileSize,
            recordingMode: recordingMode,
            originName: originName,
            destinationName: destinationName
        )

        context.insert(recording)
        save()
    }

    func fetchRecordings() -> [Recording] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("[DataService] fetchRecordings error: \(error)")
            return []
        }
    }

    func deleteRecording(_ recording: Recording) {
        guard let context = modelContext else { return }
        try? FileManager.default.removeItem(at: recording.fileURL)
        context.delete(recording)
        save()
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
