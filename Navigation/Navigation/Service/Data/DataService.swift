import Foundation
import SwiftData
import CoreLocation

final class DataService {

    static let shared = DataService()

    // MARK: - Storage Limits

    /// 무한정 쌓이지 않도록 하는 상한. 초과분은 가장 오래된/오래 안 쓴 것부터 자동 정리(무음).
    static let maxSearchHistoryCount = 50
    static let maxFavoriteCount = 200

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
        trimSearchHistoryIfNeeded()
    }

    /// 상한 초과 시 가장 오래된 검색기록부터 삭제 (fetchRecentSearches가 최신순 정렬이므로 뒤쪽이 오래된 것)
    private func trimSearchHistoryIfNeeded() {
        let all = fetchRecentSearches(limit: Int.max)
        guard all.count > Self.maxSearchHistoryCount, let context = modelContext else { return }
        for item in all.suffix(from: Self.maxSearchHistoryCount) {
            context.delete(item)
        }
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
        trimFavoritesIfNeeded()
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
        trimFavoritesIfNeeded()
    }

    /// 상한 초과 시 가장 오래 안 쓴(lastUsedAt 오래된) 즐겨찾기부터 삭제
    /// (fetchFavorites가 lastUsedAt 최신순 정렬이므로 뒤쪽이 가장 오래 안 쓴 것)
    private func trimFavoritesIfNeeded() {
        let all = fetchFavorites()
        guard all.count > Self.maxFavoriteCount, let context = modelContext else { return }
        for item in all.suffix(from: Self.maxFavoriteCount) {
            context.delete(item)
        }
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
        let threshold = 0.0001 // ~10m

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

    // MARK: - Parking (FR-019/020/021)

    func fetchActiveParkingSession() -> ParkingSessionRecord? {
        guard let context = modelContext else { return nil }

        let activeRaw = ParkingSessionRecord.Status.active.rawValue
        let descriptor = FetchDescriptor<ParkingSessionRecord>(
            predicate: #Predicate { $0.statusRaw == activeRaw }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            print("[DataService] fetchActiveParkingSession error: \(error)")
            return nil
        }
    }

    /// 신규 활성 세션 저장. 기존 활성 세션이 있으면 대체(사진 파일 포함 삭제) — 활성은 항상 ≤1.
    func saveParkingSession(_ record: ParkingSessionRecord) {
        guard let context = modelContext else { return }

        if let existing = fetchActiveParkingSession() {
            deleteParkingSession(existing)
            print("[ParkingFinder] replaced active session (old removed, photos deleted)")
        }

        context.insert(record)
        save()
    }

    /// 완료 처리 + 보관 정책: 완료 기록은 최근 1건만 남기고 이전 완료 기록(사진 포함) 삭제.
    func completeParkingSession(_ record: ParkingSessionRecord, by trigger: String) {
        guard let context = modelContext else { return }

        record.status = .completed
        record.completedAt = Date()

        let completedRaw = ParkingSessionRecord.Status.completed.rawValue
        let descriptor = FetchDescriptor<ParkingSessionRecord>(
            predicate: #Predicate { $0.statusRaw == completedRaw },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        if let completed = try? context.fetch(descriptor) {
            for old in completed.dropFirst() {
                deleteParkingSession(old)
            }
        }

        save()
        print("[ParkingFinder] session completed by=\(trigger), retained=1")
    }

    /// 목표 코드 즉시 수정 (FR-002a): 인접 코드 중 하나를 새 목표로 교체.
    /// 이전 목표는 인접으로 강등 — 거리는 대칭이라 그대로 유효, 그 외 인접의 거리는 미지로 초기화.
    func swapParkingTarget(_ record: ParkingSessionRecord, to neighbor: NeighborCode) {
        let oldTarget = NeighborCode(
            codeRaw: record.targetCodeRaw,
            zoneToken: record.zoneToken,
            numberValue: record.numberValue,
            distanceToTarget: neighbor.distanceToTarget
        )

        record.targetCodeRaw = neighbor.codeRaw
        record.zoneToken = neighbor.zoneToken
        record.numberValue = neighbor.numberValue

        var updated: [NeighborCode] = [oldTarget]
        for other in record.neighbors where other.codeRaw != neighbor.codeRaw {
            updated.append(NeighborCode(
                codeRaw: other.codeRaw,
                zoneToken: other.zoneToken,
                numberValue: other.numberValue,
                distanceToTarget: nil
            ))
        }
        record.neighbors = updated

        save()
        print("[ParkingFinder] target swapped to \(neighbor.codeRaw)")
    }

    private func deleteParkingSession(_ record: ParkingSessionRecord) {
        guard let context = modelContext else { return }
        for url in record.photoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        context.delete(record)
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
