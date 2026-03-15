import Combine
import MapKit

enum RegionSearchMode {
    case biased
    case strict
}

protocol SearchProviding: AnyObject {

    var completionsPublisher: CurrentValueSubject<[SearchCompletion], Never> { get }
    var queryCompletionsPublisher: CurrentValueSubject<[SearchCompletion], Never> { get }
    var isSearchingPublisher: CurrentValueSubject<Bool, Never> { get }
    var errorPublisher: PassthroughSubject<Error, Never> { get }
    var currentRegion: MKCoordinateRegion? { get }
    var supportedCategories: [SearchCategory] { get }

    func updateRegion(_ region: MKCoordinateRegion)
    func updateQuery(_ fragment: String)
    func search(for completion: SearchCompletion) async throws -> [Place]
    func search(query: String, region: MKCoordinateRegion?, regionMode: RegionSearchMode) async throws -> [Place]
    func searchCategory(_ category: SearchCategory, region: MKCoordinateRegion?, regionMode: RegionSearchMode) async throws -> [Place]
    func cancelCurrentSearch()

    // Pagination
    var hasMoreResults: CurrentValueSubject<Bool, Never> { get }
    func loadMoreResults() async throws -> [Place]
}

extension SearchProviding {
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] {
        try await search(query: query, region: region, regionMode: .biased)
    }

    func searchCategory(_ category: SearchCategory, region: MKCoordinateRegion?, regionMode: RegionSearchMode) async throws -> [Place] {
        try await search(query: category.query, region: region, regionMode: regionMode)
    }

    // Default: no pagination support
    var hasMoreResults: CurrentValueSubject<Bool, Never> {
        CurrentValueSubject(false)
    }

    func loadMoreResults() async throws -> [Place] { [] }
}
