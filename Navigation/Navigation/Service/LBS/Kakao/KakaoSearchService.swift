import Combine
import MapKit

final class KakaoSearchService: SearchProviding {

    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    private(set) var currentRegion: MKCoordinateRegion?
    private var searchTask: Task<Void, Never>?

    func updateRegion(_ region: MKCoordinateRegion) {
        currentRegion = region
    }

    func updateQuery(_ fragment: String) {
        searchTask?.cancel()
        guard !fragment.isEmpty else {
            completionsPublisher.send([])
            queryCompletionsPublisher.send([])
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            do {
                let results = try await fetchKeywordSearch(query: fragment, region: self.currentRegion)
                let completions = results.map { doc in
                    SearchCompletion(
                        id: "kakao_\(doc.placeName)_\(doc.x)_\(doc.y)",
                        title: doc.placeName,
                        subtitle: doc.roadAddressName ?? doc.addressName
                    )
                }
                completionsPublisher.send(completions)
            } catch {
                if !Task.isCancelled { errorPublisher.send(error) }
            }
        }
    }

    func search(for completion: SearchCompletion) async throws -> [Place] {
        try await search(query: completion.title, region: currentRegion)
    }

    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] {
        isSearchingPublisher.send(true)
        defer { isSearchingPublisher.send(false) }

        let docs = try await fetchKeywordSearch(query: query, region: region)
        return docs.map { KakaoModelConverter.place(from: $0) }
    }

    func cancelCurrentSearch() {
        searchTask?.cancel()
    }

    // MARK: - Private

    private func fetchKeywordSearch(
        query: String,
        region: MKCoordinateRegion? = nil
    ) async throws -> [KakaoSearchResponse.Document] {
        var queryItems = [URLQueryItem(name: "query", value: query)]

        if let region {
            queryItems.append(URLQueryItem(name: "x", value: "\(region.center.longitude)"))
            queryItems.append(URLQueryItem(name: "y", value: "\(region.center.latitude)"))
            // sort 미지정 → 기본값 accuracy (정확도순, 위치 참고)
        }

        let response: KakaoSearchResponse = try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/search/keyword.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )
        return response.documents
    }
}
