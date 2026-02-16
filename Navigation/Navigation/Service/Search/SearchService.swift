import MapKit
import Combine

final class SearchService: NSObject {

    // MARK: - Publishers

    let completionsPublisher = CurrentValueSubject<[MKLocalSearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    // MARK: - Private

    private let completer = MKLocalSearchCompleter()
    private var currentSearch: MKLocalSearch?

    // MARK: - Init

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address, .query]
    }

    // MARK: - Public Methods

    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func updateQuery(_ fragment: String) {
        if fragment.isEmpty {
            completionsPublisher.send([])
            completer.queryFragment = ""
        } else {
            completer.queryFragment = fragment
        }
    }

    func search(for completion: MKLocalSearchCompletion) async throws -> [MKMapItem] {
        cancelCurrentSearch()
        isSearchingPublisher.send(true)

        let request = MKLocalSearch.Request(completion: completion)
        request.region = completer.region

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
            completionsPublisher.send(completer.results)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            errorPublisher.send(error)
        }
    }
}
