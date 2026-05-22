import Foundation
import Combine
import MapKit

final class SearchViewModel {

    // MARK: - Publishers

    let completions = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletions = CurrentValueSubject<[SearchCompletion], Never>([])
    let isLoading = CurrentValueSubject<Bool, Never>(false)
    let hasMoreResults = CurrentValueSubject<Bool, Never>(false)
    let errorMessage = CurrentValueSubject<String?, Never>(nil)
    let recentSearches = CurrentValueSubject<[SearchHistory], Never>([])

    // MARK: - Private

    private var searchService: SearchProviding
    private let dataService: DataService
    private var cancellables = Set<AnyCancellable>()
    private var serviceCancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(searchService: SearchProviding, dataService: DataService = .shared) {
        self.searchService = searchService
        self.dataService = dataService
        bindSearchService()
        observeProviderChange()
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

    func selectCompletion(_ completion: SearchCompletion) async -> [Place]? {
        do {
            let results = try await searchService.search(for: completion)
            return results
        } catch {
            errorMessage.send("검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func executeSearch(query: String) async -> [Place]? {
        guard !query.isEmpty else { return nil }
        do {
            let results = try await searchService.search(query: query, region: searchService.currentRegion)
            return results
        } catch {
            errorMessage.send("검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func selectRecentSearch(_ history: SearchHistory) -> [Place] {
        let place = Place(
            name: history.placeName,
            coordinate: CLLocationCoordinate2D(latitude: history.latitude, longitude: history.longitude),
            address: nil,
            phoneNumber: nil,
            url: nil,
            category: nil,
            providerRawData: nil
        )
        return [place]
    }

    func deleteRecentSearch(_ history: SearchHistory) {
        dataService.deleteSearchHistory(history)
        loadRecentSearches()
    }

    func clearAllRecentSearches() {
        dataService.clearAllSearchHistory()
        recentSearches.send([])
    }

    func loadMore() async -> [Place]? {
        guard hasMoreResults.value else { return nil }
        do {
            let more = try await searchService.loadMoreResults()
            return more.isEmpty ? nil : more
        } catch {
            errorMessage.send("추가 검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func clearSearch() {
        searchService.updateQuery("")
        errorMessage.send(nil)
    }

    // MARK: - Private

    private func bindSearchService() {
        serviceCancellables.removeAll()

        searchService.completionsPublisher
            .sink { [weak self] in self?.completions.send($0) }
            .store(in: &serviceCancellables)

        searchService.queryCompletionsPublisher
            .sink { [weak self] in self?.queryCompletions.send($0) }
            .store(in: &serviceCancellables)

        searchService.isSearchingPublisher
            .sink { [weak self] in self?.isLoading.send($0) }
            .store(in: &serviceCancellables)

        searchService.hasMoreResults
            .sink { [weak self] in self?.hasMoreResults.send($0) }
            .store(in: &serviceCancellables)

        searchService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage.send("검색 오류: \(error.localizedDescription)")
            }
            .store(in: &serviceCancellables)
    }

    private func observeProviderChange() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProviderChanged),
            name: .lbsSearchProviderChanged,
            object: nil
        )
    }

    @objc private func handleProviderChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.searchService.cancelCurrentSearch()
            self?.searchService = LBSServiceProvider.shared.search
            self?.bindSearchService()
            self?.completions.send([])
            self?.queryCompletions.send([])
        }
    }
}
