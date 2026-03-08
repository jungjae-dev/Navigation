import MapKit
import Combine

final class AppleSearchService: NSObject, SearchProviding {

    // MARK: - Publishers

    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    // MARK: - Private

    private let completer = MKLocalSearchCompleter()
    private let queryCompleter = MKLocalSearchCompleter()
    private var currentSearch: MKLocalSearch?
    private var completionMap: [String: MKLocalSearchCompletion] = [:]

    // MARK: - Init

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]

        queryCompleter.delegate = self
        queryCompleter.resultTypes = .query
    }

    // MARK: - SearchProviding

    var currentRegion: MKCoordinateRegion? { completer.region }

    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
        queryCompleter.region = region
    }

    func updateQuery(_ fragment: String) {
        if fragment.isEmpty {
            completionsPublisher.send([])
            queryCompletionsPublisher.send([])
            completionMap.removeAll()
            completer.queryFragment = ""
            queryCompleter.queryFragment = ""
        } else {
            completer.queryFragment = fragment
            queryCompleter.queryFragment = fragment
        }
    }

    func search(for completion: SearchCompletion) async throws -> [Place] {
        guard let mkCompletion = completionMap[completion.id] else {
            throw LBSError.completionNotFound
        }

        cancelCurrentSearch()
        isSearchingPublisher.send(true)

        let request = MKLocalSearch.Request(completion: mkCompletion)
        request.region = completer.region

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            isSearchingPublisher.send(false)
            return response.mapItems.map { AppleModelConverter.place(from: $0) }
        } catch {
            isSearchingPublisher.send(false)
            throw error
        }
    }

    func search(query: String, region: MKCoordinateRegion? = nil, regionMode: RegionSearchMode = .biased) async throws -> [Place] {
        cancelCurrentSearch()
        isSearchingPublisher.send(true)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region {
            request.region = region
        } else {
            request.region = completer.region
        }
        request.regionPriority = (regionMode == .strict) ? .required : .default

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            isSearchingPublisher.send(false)
            return response.mapItems.map { AppleModelConverter.place(from: $0) }
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

extension AppleSearchService: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            let results = completer.results
            let converted = results.map { mkCompletion -> SearchCompletion in
                let sc = AppleModelConverter.searchCompletion(from: mkCompletion)
                completionMap[sc.id] = mkCompletion
                return sc
            }

            if completer === self.queryCompleter {
                queryCompletionsPublisher.send(converted)
            } else {
                completionsPublisher.send(converted)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let label = completer === self.queryCompleter ? "queryCompleter" : "completer"
            print("[AppleSearchService] \(label) error: \(error.localizedDescription)")
        }
    }
}
