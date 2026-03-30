# Phase 4: Kakao 구현체 추가

## 목표
Phase 1의 프로토콜(SearchProviding, RouteProviding, GeocodingProviding)에 맞는
**Kakao API 구현체**를 추가한다. Phase 3까지 완료된 상태에서 프로토콜만 구현하면 바로 교체 가능하다.

---

## 4-1. Kakao API 개요

### 사용 API 목록

| 기능 | API | 엔드포인트 | 인증 |
|---|---|---|---|
| 키워드 검색 | Kakao Local | `GET /v2/local/search/keyword` | REST API 키 |
| 카테고리 검색 | Kakao Local | `GET /v2/local/search/category` | REST API 키 |
| 주소 검색 | Kakao Local | `GET /v2/local/search/address` | REST API 키 |
| 좌표 → 주소 | Kakao Local | `GET /v2/local/geo/coord2address` | REST API 키 |
| 주소 → 좌표 | Kakao Local | `GET /v2/local/search/address` | REST API 키 |
| 자동차 길찾기 | Kakao Mobility | `POST /v1/waypoints/directions` | 앱 키 |
| 도보 길찾기 | 미지원 (Apple fallback) | — | — |

### 할당량

| API | 무료 할당량 | 초과 시 |
|---|---|---|
| Kakao Local (검색/지오코딩) | 일 30,000건 | HTTP 429 |
| Kakao Mobility (길찾기) | 월 5,000건 | HTTP 429 / 402 |

---

## 4-2. 공통 네트워크 레이어

### 파일 위치
```
Navigation/Service/LBS/Kakao/
├── KakaoAPIClient.swift
├── KakaoAPIConfig.swift
├── KakaoSearchService.swift
├── KakaoRouteService.swift
└── KakaoGeocodingService.swift
```

### KakaoAPIConfig.swift
```swift
enum KakaoAPIConfig {
    // 키는 Info.plist 또는 Keychain에서 읽기
    static var restAPIKey: String {
        Bundle.main.infoDictionary?["KAKAO_REST_API_KEY"] as? String ?? ""
    }

    static var mobilityAppKey: String {
        Bundle.main.infoDictionary?["KAKAO_MOBILITY_APP_KEY"] as? String ?? ""
    }

    enum BaseURL {
        static let local = "https://dapi.kakao.com"
        static let mobility = "https://apis-navi.kakaomobility.com"
    }
}
```

### KakaoAPIClient.swift
```swift
final class KakaoAPIClient {
    static let shared = KakaoAPIClient()

    func request<T: Decodable>(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem],
        apiKey: String
    ) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LBSError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 429:
            throw LBSError.quotaExceeded
        default:
            throw LBSError.networkError(
                NSError(domain: "KakaoAPI", code: httpResponse.statusCode)
            )
        }
    }
}
```

---

## 4-3. Kakao 응답 모델 (Decodable)

### 파일 위치
```
Navigation/Service/LBS/Kakao/Model/
├── KakaoSearchResponse.swift
├── KakaoRouteResponse.swift
└── KakaoGeocodingResponse.swift
```

### KakaoSearchResponse.swift
```swift
struct KakaoSearchResponse: Decodable {
    let meta: Meta
    let documents: [Document]

    struct Meta: Decodable {
        let totalCount: Int
        let pageableCount: Int
        let isEnd: Bool

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case pageableCount = "pageable_count"
            case isEnd = "is_end"
        }
    }

    struct Document: Decodable {
        let placeName: String
        let addressName: String
        let roadAddressName: String?
        let phone: String?
        let categoryName: String?
        let x: String   // longitude
        let y: String   // latitude

        enum CodingKeys: String, CodingKey {
            case placeName = "place_name"
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
            case phone
            case categoryName = "category_name"
            case x, y
        }
    }
}
```

### KakaoRouteResponse.swift
```swift
struct KakaoRouteResponse: Decodable {
    let routes: [KakaoRoute]

    struct KakaoRoute: Decodable {
        let resultCode: Int
        let resultMessage: String
        let summary: Summary
        let sections: [Section]

        enum CodingKeys: String, CodingKey {
            case resultCode = "result_code"
            case resultMessage = "result_message"
            case summary, sections
        }
    }

    struct Summary: Decodable {
        let distance: Int          // 미터
        let duration: Int          // 초
    }

    struct Section: Decodable {
        let distance: Int
        let duration: Int
        let roads: [Road]
        let guides: [Guide]
    }

    struct Road: Decodable {
        let vertexes: [Double]     // [lng, lat, lng, lat, ...] 쌍으로 나열
    }

    struct Guide: Decodable {
        let name: String
        let x: Double
        let y: Double
        let distance: Int
        let duration: Int
        let type: Int              // 턴 타입 코드
        let guidance: String       // 안내 텍스트
    }
}
```

---

## 4-4. KakaoSearchService

```swift
final class KakaoSearchService: SearchProviding {
    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    private var currentRegion: MKCoordinateRegion?
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

        // Debounce: 300ms 후 API 호출
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            do {
                let results = try await fetchKeywordSearch(query: fragment)
                let completions = results.map { doc in
                    SearchCompletion(
                        id: "kakao_\(doc.placeName)_\(doc.x)_\(doc.y)",
                        title: doc.placeName,
                        subtitle: doc.roadAddressName ?? doc.addressName,
                        highlightRanges: nil
                    )
                }
                completionsPublisher.send(completions)
            } catch {
                errorPublisher.send(error)
            }
        }
    }

    func search(for completion: SearchCompletion) async throws -> [Place] {
        // completion.title로 재검색 (Kakao는 completion 객체 재사용 불필요)
        return try await search(query: completion.title, region: currentRegion)
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
            let radius = Int(max(region.span.latitudeDelta, region.span.longitudeDelta) * 111_000 / 2)
            queryItems.append(URLQueryItem(name: "radius", value: "\(min(radius, 20000))"))
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
```

**참고:** Kakao 검색 API는 자동완성 전용 API가 없으므로, `updateQuery`에서 debounce 후 키워드 검색을 호출하여 유사하게 구현한다. Apple의 `MKLocalSearchCompleter`와 달리 **query 자동완성(쿼리 제안)**은 지원하지 않는다.

---

## 4-5. KakaoRouteService

```swift
final class KakaoRouteService: RouteProviding {
    private var currentTask: Task<[Route], Error>?

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        cancelCurrentRequest()

        // Kakao Mobility는 도보 미지원 → 도보 요청 시 에러
        guard transportMode == .automobile else {
            throw LBSError.noRoutesFound
        }

        let task = Task {
            let queryItems = [
                URLQueryItem(name: "origin", value: "\(origin.longitude),\(origin.latitude)"),
                URLQueryItem(name: "destination", value: "\(destination.longitude),\(destination.latitude)"),
                URLQueryItem(name: "alternatives", value: "true"),  // 대안 경로
            ]

            let response: KakaoRouteResponse = try await KakaoAPIClient.shared.request(
                baseURL: KakaoAPIConfig.BaseURL.mobility,
                path: "/v1/directions",
                queryItems: queryItems,
                apiKey: KakaoAPIConfig.mobilityAppKey
            )

            let routes = response.routes
                .filter { $0.resultCode == 0 }
                .map { KakaoModelConverter.route(from: $0) }

            guard !routes.isEmpty else { throw LBSError.noRoutesFound }
            return routes
        }

        currentTask = task
        return try await task.value
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let routes = try await calculateRoutes(
            from: origin, to: destination, transportMode: .automobile
        )
        guard let first = routes.first else { throw LBSError.noRoutesFound }
        return first.expectedTravelTime
    }

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

---

## 4-6. KakaoGeocodingService

```swift
final class KakaoGeocodingService: GeocodingProviding {

    func reverseGeocode(location: CLLocation) async throws -> Place {
        let queryItems = [
            URLQueryItem(name: "x", value: "\(location.coordinate.longitude)"),
            URLQueryItem(name: "y", value: "\(location.coordinate.latitude)"),
        ]

        let response: KakaoGeocodingResponse = try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/geo/coord2address.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )

        guard let doc = response.documents.first else {
            throw LBSError.noResults
        }

        return Place(
            name: nil,
            coordinate: location.coordinate,
            address: doc.address?.addressName ?? doc.roadAddress?.addressName,
            phoneNumber: nil,
            category: nil,
            providerRawData: doc
        )
    }

    func geocode(address: String) async throws -> Place {
        let queryItems = [
            URLQueryItem(name: "query", value: address),
        ]

        let response: KakaoSearchResponse = try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/search/address.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )

        guard let doc = response.documents.first,
              let lat = Double(doc.y),
              let lng = Double(doc.x) else {
            throw LBSError.noResults
        }

        return Place(
            name: doc.placeName,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            address: doc.addressName,
            phoneNumber: nil,
            category: nil,
            providerRawData: doc
        )
    }
}
```

---

## 4-7. KakaoModelConverter

### 파일 위치
```
Navigation/Service/LBS/Kakao/KakaoModelConverter.swift
```

```swift
enum KakaoModelConverter {

    static func place(from doc: KakaoSearchResponse.Document) -> Place {
        let lat = Double(doc.y) ?? 0
        let lng = Double(doc.x) ?? 0
        return Place(
            name: doc.placeName,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            address: doc.roadAddressName ?? doc.addressName,
            phoneNumber: doc.phone,
            category: doc.categoryName,
            providerRawData: doc
        )
    }

    static func route(from kakaoRoute: KakaoRouteResponse.KakaoRoute) -> Route {
        // polyline 좌표 추출 (vertexes: [lng, lat, lng, lat, ...])
        var coordinates: [CLLocationCoordinate2D] = []
        for section in kakaoRoute.sections {
            for road in section.roads {
                let vertexes = road.vertexes
                for i in stride(from: 0, to: vertexes.count - 1, by: 2) {
                    coordinates.append(
                        CLLocationCoordinate2D(latitude: vertexes[i + 1], longitude: vertexes[i])
                    )
                }
            }
        }

        // steps 추출 (guides)
        let steps = kakaoRoute.sections.flatMap { section in
            section.guides.map { guide in
                RouteStep(
                    instructions: guide.guidance,
                    distance: CLLocationDistance(guide.distance),
                    polylineCoordinates: [
                        CLLocationCoordinate2D(latitude: guide.y, longitude: guide.x)
                    ]
                )
            }
        }

        return Route(
            id: UUID().uuidString,
            distance: CLLocationDistance(kakaoRoute.summary.distance),
            expectedTravelTime: TimeInterval(kakaoRoute.summary.duration),
            name: "",
            steps: steps,
            polylineCoordinates: coordinates,
            transportMode: .automobile
        )
    }
}
```

---

## 4-8. LBSServiceProvider Kakao 분기 추가

```swift
// ServiceProvider.swift 수정
case .kakao:
    search = KakaoSearchService()
    route = KakaoRouteService()
    geocoding = KakaoGeocodingService()
```

---

## 4-9. Kakao 도보 경로 미지원 대응

Kakao Mobility는 도보 길찾기를 지원하지 않는다.

**대응 방안:**
1. TransportMode가 `.walking`일 때 자동으로 Apple fallback
2. 또는 UI에서 Kakao 선택 시 도보 옵션 비활성화

권장: FallbackService에서 처리 (Phase 5)

---

## 검증 항목

| # | 검증 내용 | 방법 |
|---|---|---|
| V4-1 | Kakao REST API 키 설정 후 키워드 검색 응답 정상 | 단위 테스트 (실제 API 호출) |
| V4-2 | Kakao 검색 결과 → Place 변환 정확도 (좌표, 이름, 주소) | 단위 테스트 |
| V4-3 | Kakao 길찾기 응답 → Route 변환 정확도 (거리, 시간, polyline) | 단위 테스트 |
| V4-4 | Kakao Route의 polyline이 지도 overlay에 정상 표시되는가 | 시뮬레이터 시각 확인 |
| V4-5 | Kakao Route의 guides → RouteStep이 GuidanceEngine에서 정상 동작하는가 | VirtualDrive 테스트 |
| V4-6 | Kakao 역지오코딩 결과 정상 | 단위 테스트 |
| V4-7 | LBSServiceProvider에서 `.kakao` 선택 시 정상 초기화 | 앱 실행 확인 |
| V4-8 | 할당량 초과 시 LBSError.quotaExceeded 정상 throw | HTTP 429 mock 테스트 |
| V4-9 | Kakao 검색 debounce (300ms) 정상 동작 | 빠른 타이핑 테스트 |
| V4-10 | Kakao 도보 경로 요청 시 에러 처리 정상 | `.walking` 모드 테스트 |
| V4-11 | API 키 미설정 시 명확한 에러 메시지 | 빈 키로 테스트 |
