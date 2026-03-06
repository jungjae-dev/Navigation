import Combine
import MapKit

final class FallbackSearchService: SearchProviding {

    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    private let primary: SearchProviding
    private let fallback: SearchProviding
    private var cancellables = Set<AnyCancellable>()

    init(primary: SearchProviding, fallback: SearchProviding) {
        self.primary = primary
        self.fallback = fallback
        bindPrimary()
    }

    var currentRegion: MKCoordinateRegion? { primary.currentRegion }

    func updateRegion(_ region: MKCoordinateRegion) {
        primary.updateRegion(region)
        fallback.updateRegion(region)
    }

    func updateQuery(_ fragment: String) {
        primary.updateQuery(fragment)
    }

    func search(for completion: SearchCompletion) async throws -> [Place] {
        do {
            return try await primary.search(for: completion)
        } catch let error as LBSError where error == .quotaExceeded {
            return try await fallback.search(query: completion.title, region: nil)
        }
    }

    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] {
        do {
            return try await primary.search(query: query, region: region)
        } catch let error as LBSError where error == .quotaExceeded {
            return try await fallback.search(query: query, region: region)
        }
    }

    func cancelCurrentSearch() {
        primary.cancelCurrentSearch()
        fallback.cancelCurrentSearch()
    }

    // MARK: - Private

    private func bindPrimary() {
        primary.completionsPublisher
            .sink { [weak self] in self?.completionsPublisher.send($0) }
            .store(in: &cancellables)

        primary.queryCompletionsPublisher
            .sink { [weak self] in self?.queryCompletionsPublisher.send($0) }
            .store(in: &cancellables)

        primary.isSearchingPublisher
            .sink { [weak self] in self?.isSearchingPublisher.send($0) }
            .store(in: &cancellables)

        primary.errorPublisher
            .sink { [weak self] in self?.errorPublisher.send($0) }
            .store(in: &cancellables)
    }
}
