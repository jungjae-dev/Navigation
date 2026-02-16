import Foundation
import Combine
import MapKit

final class SearchViewModel {

    // MARK: - Publishers

    let completions: CurrentValueSubject<[MKLocalSearchCompletion], Never>
    let isLoading: CurrentValueSubject<Bool, Never>
    let errorMessage = CurrentValueSubject<String?, Never>(nil)
    let recentSearches = CurrentValueSubject<[SearchHistory], Never>([])

    // MARK: - Private

    private let searchService: SearchService
    private let dataService: DataService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(searchService: SearchService, dataService: DataService = .shared) {
        self.searchService = searchService
        self.dataService = dataService
        self.completions = searchService.completionsPublisher
        self.isLoading = searchService.isSearchingPublisher

        searchService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage.send("검색 오류: \(error.localizedDescription)")
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func loadRecentSearches() {
        let searches = dataService.fetchRecentSearches(limit: 20)
        recentSearches.send(searches)
    }

    func updateSearchRegion(_ region: MKCoordinateRegion) {
        searchService.updateRegion(region)
    }

    func updateQuery(_ query: String) {
        searchService.updateQuery(query)
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion) async -> [MKMapItem]? {
        do {
            let results = try await searchService.search(for: completion)

            // Save to history
            if let firstItem = results.first {
                dataService.saveSearchHistory(query: completion.title, mapItem: firstItem)
            }

            return results
        } catch {
            errorMessage.send("검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func executeSearch(query: String) async -> [MKMapItem]? {
        guard !query.isEmpty else { return nil }
        do {
            let results = try await searchService.search(query: query)

            // Save to history
            if let firstItem = results.first {
                dataService.saveSearchHistory(query: query, mapItem: firstItem)
            }

            return results
        } catch {
            errorMessage.send("검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func selectRecentSearch(_ history: SearchHistory) -> [MKMapItem] {
        // Create MKMapItem from saved history
        let location = CLLocation(latitude: history.latitude, longitude: history.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = history.placeName
        return [mapItem]
    }

    func deleteRecentSearch(_ history: SearchHistory) {
        dataService.deleteSearchHistory(history)
        loadRecentSearches()
    }

    func clearAllRecentSearches() {
        dataService.clearAllSearchHistory()
        recentSearches.send([])
    }

    func clearSearch() {
        searchService.updateQuery("")
        errorMessage.send(nil)
    }
}
