import Combine
import MapKit

final class KakaoSearchService: SearchProviding {

    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()
    let hasMoreResults = CurrentValueSubject<Bool, Never>(false)

    let supportedCategories = SearchCategory.kakaoAll

    private(set) var currentRegion: MKCoordinateRegion?
    private var searchTask: Task<Void, Never>?

    // MARK: - Pagination State

    private var currentPage = 1
    private var lastSearchContext: SearchContext?

    private enum SearchContext {
        case keyword(query: String, region: MKCoordinateRegion?, regionMode: RegionSearchMode)
        case category(code: String, region: MKCoordinateRegion?, regionMode: RegionSearchMode)
    }

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
                let response = try await fetchKeywordSearch(query: fragment, region: self.currentRegion)
                let completions = response.documents.map { doc in
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

    func search(query: String, region: MKCoordinateRegion?, regionMode: RegionSearchMode = .biased) async throws -> [Place] {
        resetPagination()
        lastSearchContext = .keyword(query: query, region: region, regionMode: regionMode)

        isSearchingPublisher.send(true)
        defer { isSearchingPublisher.send(false) }

        let response = try await fetchKeywordSearch(query: query, region: region, regionMode: regionMode, page: 1)
        hasMoreResults.send(!response.meta.isEnd)
        return response.documents.map { KakaoModelConverter.place(from: $0) }
    }

    func searchCategory(_ category: SearchCategory, region: MKCoordinateRegion?, regionMode: RegionSearchMode = .biased) async throws -> [Place] {
        guard let code = category.kakaoCategoryCode else {
            return try await search(query: category.query, region: region, regionMode: regionMode)
        }

        resetPagination()
        lastSearchContext = .category(code: code, region: region, regionMode: regionMode)

        isSearchingPublisher.send(true)
        defer { isSearchingPublisher.send(false) }

        let response = try await fetchCategorySearch(categoryCode: code, region: region, regionMode: regionMode, page: 1)
        hasMoreResults.send(!response.meta.isEnd)
        return response.documents.map { KakaoModelConverter.place(from: $0) }
    }

    func loadMoreResults() async throws -> [Place] {
        guard hasMoreResults.value, let context = lastSearchContext else { return [] }

        let nextPage = currentPage + 1

        let response: KakaoSearchResponse
        switch context {
        case .keyword(let query, let region, let regionMode):
            response = try await fetchKeywordSearch(query: query, region: region, regionMode: regionMode, page: nextPage)
        case .category(let code, let region, let regionMode):
            response = try await fetchCategorySearch(categoryCode: code, region: region, regionMode: regionMode, page: nextPage)
        }

        currentPage = nextPage
        hasMoreResults.send(!response.meta.isEnd)
        return response.documents.map { KakaoModelConverter.place(from: $0) }
    }

    func cancelCurrentSearch() {
        searchTask?.cancel()
    }

    // MARK: - Private

    private func resetPagination() {
        currentPage = 1
        hasMoreResults.send(false)
        lastSearchContext = nil
    }

    private func fetchKeywordSearch(
        query: String,
        region: MKCoordinateRegion? = nil,
        regionMode: RegionSearchMode = .biased,
        page: Int = 1
    ) async throws -> KakaoSearchResponse {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        if let region {
            if regionMode == .strict {
                let lat = region.center.latitude
                let lon = region.center.longitude
                let dLat = region.span.latitudeDelta / 2
                let dLon = region.span.longitudeDelta / 2
                let rect = "\(lon - dLon),\(lat - dLat),\(lon + dLon),\(lat + dLat)"
                queryItems.append(URLQueryItem(name: "rect", value: rect))
                queryItems.append(URLQueryItem(name: "x", value: "\(lon)"))
                queryItems.append(URLQueryItem(name: "y", value: "\(lat)"))
                queryItems.append(URLQueryItem(name: "sort", value: "distance"))
            } else {
                queryItems.append(URLQueryItem(name: "x", value: "\(region.center.longitude)"))
                queryItems.append(URLQueryItem(name: "y", value: "\(region.center.latitude)"))
            }
        }

        return try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/search/keyword.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )
    }

    private func fetchCategorySearch(
        categoryCode: String,
        region: MKCoordinateRegion? = nil,
        regionMode: RegionSearchMode = .biased,
        page: Int = 1
    ) async throws -> KakaoSearchResponse {
        var queryItems = [
            URLQueryItem(name: "category_group_code", value: categoryCode),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        if let region {
            if regionMode == .strict {
                let lat = region.center.latitude
                let lon = region.center.longitude
                let dLat = region.span.latitudeDelta / 2
                let dLon = region.span.longitudeDelta / 2
                let rect = "\(lon - dLon),\(lat - dLat),\(lon + dLon),\(lat + dLat)"
                queryItems.append(URLQueryItem(name: "rect", value: rect))
                queryItems.append(URLQueryItem(name: "sort", value: "distance"))
            } else {
                queryItems.append(URLQueryItem(name: "x", value: "\(region.center.longitude)"))
                queryItems.append(URLQueryItem(name: "y", value: "\(region.center.latitude)"))
                queryItems.append(URLQueryItem(name: "sort", value: "distance"))
            }
        }

        return try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/search/category.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )
    }
}
