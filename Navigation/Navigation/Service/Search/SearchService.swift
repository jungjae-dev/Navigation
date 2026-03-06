import MapKit
import Combine

final class SearchService: NSObject {

    // MARK: - Publishers

    let completionsPublisher = CurrentValueSubject<[MKLocalSearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    // MARK: - Query Completions (for smart search)

    let queryCompletionsPublisher = CurrentValueSubject<[MKLocalSearchCompletion], Never>([])

    // MARK: - Private

    private let completer = MKLocalSearchCompleter()
    private let queryCompleter = MKLocalSearchCompleter()
    private var currentSearch: MKLocalSearch?

    // MARK: - Init

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]

        queryCompleter.delegate = self
        queryCompleter.resultTypes = .query
    }

    // MARK: - Public Methods

    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
        queryCompleter.region = region
    }

    func updateQuery(_ fragment: String) {
        if fragment.isEmpty {
            completionsPublisher.send([])
            queryCompletionsPublisher.send([])
            completer.queryFragment = ""
            queryCompleter.queryFragment = ""
        } else {
            completer.queryFragment = fragment
            queryCompleter.queryFragment = fragment
        }
    }

    func search(for completion: MKLocalSearchCompletion) async throws -> [MKMapItem] {
        cancelCurrentSearch()
        isSearchingPublisher.send(true)

        let request = MKLocalSearch.Request(completion: completion)
        request.region = completer.region
        request.regionPriority = .default

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            isSearchingPublisher.send(false)
            return response.mapItems
        } catch {
            isSearchingPublisher.send(false)
            throw error
        }
    }

    func search(query: String, region: MKCoordinateRegion? = nil) async throws -> [MKMapItem] {
        cancelCurrentSearch()
        isSearchingPublisher.send(true)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region {
            request.region = region
        } else {
            request.region = completer.region
        }
        request.regionPriority = .default

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            isSearchingPublisher.send(false)
            return response.mapItems
        } catch {
            isSearchingPublisher.send(false)
            throw error
        }
    }

    func cancelCurrentSearch() {
        currentSearch?.cancel()
        currentSearch = nil
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension SearchService: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            if completer === self.queryCompleter {
                queryCompletionsPublisher.send(completer.results)
            } else {
                completionsPublisher.send(completer.results)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let label = completer === self.queryCompleter ? "queryCompleter" : "completer"
            print("[SearchService] \(label) error: \(error.localizedDescription)")
        }
    }
}
