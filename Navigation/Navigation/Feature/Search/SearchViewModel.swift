import Foundation
import Combine
import MapKit

final class SearchViewModel {

    // MARK: - Publishers

    let completions: CurrentValueSubject<[MKLocalSearchCompletion], Never>
    let isLoading: CurrentValueSubject<Bool, Never>
    let errorMessage = CurrentValueSubject<String?, Never>(nil)

    // MARK: - Private

    private let searchService: SearchService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(searchService: SearchService) {
        self.searchService = searchService
        self.completions = searchService.completionsPublisher
        self.isLoading = searchService.isSearchingPublisher
    }

    // MARK: - Actions

    func updateSearchRegion(_ region: MKCoordinateRegion) {
        searchService.updateRegion(region)
    }

    func updateQuery(_ query: String) {
        searchService.updateQuery(query)
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion) async -> [MKMapItem]? {
        do {
            return try await searchService.search(for: completion)
        } catch {
            errorMessage.send("검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func executeSearch(query: String) async -> [MKMapItem]? {
        guard !query.isEmpty else { return nil }
        do {
            return try await searchService.search(query: query)
        } catch {
            errorMessage.send("검색 실패: \(error.localizedDescription)")
            return nil
        }
    }

    func clearSearch() {
        searchService.updateQuery("")
        errorMessage.send(nil)
    }
}
