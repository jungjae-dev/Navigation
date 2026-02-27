# Kakao API 마이그레이션 — 구현 계획

## 1. 개요

[KakaoAPIMigration.md](KakaoAPIMigration.md)에서 정의한 Apple MapKit → Kakao REST API 전환을 단계별로 실행하는 구현 계획이다.

### 핵심 원칙
- **Phase 0~4**: 신규 파일만 생성 → 기존 코드에 영향 없음, 빌드 항상 성공
- **Phase 5~9**: 기존 파일 수정 → 한 Phase 완료 후 빌드 확인
- **Phase 10**: 정리 → 미사용 코드 삭제

### 전체 구조

```
Phase 0  API 인프라 ──────── 신규 3개 ── 기존 코드 영향 없음
Phase 1  앱 모델 ─────────── 신규 4개 ── 기존 코드 영향 없음
Phase 2  DTO ────────────── 신규 3개 ── 기존 코드 영향 없음
Phase 3  서비스 프로토콜 ──── 신규 3개 ── 기존 코드 영향 없음
Phase 4  Kakao 서비스 ────── 신규 3개 ── 기존 코드 영향 없음
─────────── 여기까지 빌드 안전 구간 (기존 코드 변경 없음) ───────────
Phase 5  코어 엔진 ────────── 수정 7개 ── ⚠ 대규모 타입 변경
Phase 6  ViewModel ────────── 수정 3개 ── Phase 5 완료 필요
Phase 7  View ─────────────── 수정 8개 ── Phase 6 완료 필요
Phase 8  CarPlay ──────────── 수정 4개 ── Phase 5,7 완료 필요
Phase 9  Coordinator + Data ── 수정 2개 ── Phase 5~8 완료 필요
Phase 10 정리 ─────────────── 삭제 3개 ── 전체 완료 후
```

---

## 2. Phase 0 — API 인프라

### 목표
Kakao REST API를 호출하기 위한 HTTP 클라이언트, 설정, 에러 타입을 구축한다.

### 작업 목록

| # | 작업 | 파일 | 비고 |
|---|------|------|------|
| 0-1 | API 설정 | `Service/Network/KakaoAPIConfig.swift` | Info.plist에서 키 로드, BaseURL 정의 |
| 0-2 | HTTP 클라이언트 | `Service/Network/KakaoAPIClient.swift` | 싱글턴, GET/POST, `KakaoAK` 헤더 |
| 0-3 | 에러 타입 | `Service/Network/KakaoAPIError.swift` | LocalizedError 채택 |
| 0-4 | API 키 등록 | `Info.plist` | `KAKAO_REST_API_KEY` 항목 추가 |

### 상세

```
KakaoAPIConfig.swift:
┌─────────────────────────────────────────┐
│ enum KakaoAPIConfig                     │
│   static let apiKey: String             │  ← Info.plist → Bundle.main
│   enum BaseURL                          │
│     static let mobility = "apis-navi.kakaomobility.com"
│     static let local = "dapi.kakao.com" │
└─────────────────────────────────────────┘

KakaoAPIClient.swift:
┌─────────────────────────────────────────┐
│ final class KakaoAPIClient              │
│   static let shared                     │
│   func request<T: Decodable>(           │
│     url: URL,                           │
│     queryItems: [URLQueryItem],         │
│     responseType: T.Type                │
│   ) async throws -> T                   │
│                                         │
│   동작:                                  │
│   1. URLComponents → 쿼리 파라미터 조합   │
│   2. Authorization: KakaoAK {key} 헤더   │
│   3. URLSession.data(for:) 호출          │
│   4. HTTP 상태 코드 검사                  │
│   5. JSONDecoder 디코딩                  │
│   타임아웃: request 10초, resource 30초    │
└─────────────────────────────────────────┘
```

### 검증
- [x] 빌드 성공 (기존 코드 참조 없음)
- [x] API 키 정상 로드 확인 (Unit Test 또는 print)

---

## 3. Phase 1 — 앱 레벨 모델

### 목표
Apple 전용 타입(MKRoute, MKRoute.Step, MKLocalSearchCompletion, MKMapItem)을 대체할 앱 자체 모델을 정의한다.

### 작업 목록

| # | 작업 | 파일 | 대체 대상 |
|---|------|------|----------|
| 1-1 | 경로 모델 | `Model/AppRoute.swift` | MKRoute |
| 1-2 | 경로 단계 모델 | `Model/AppRouteStep.swift` | MKRoute.Step |
| 1-3 | 검색 제안 모델 | `Model/SearchSuggestion.swift` | MKLocalSearchCompletion |
| 1-4 | POI 모델 | `Model/POI.swift` | MKMapItem |

### 핵심 설계 결정

```
AppRoute:
- polyline: MKPolyline      ← MapKit 표시용, 기존 오버레이 코드 호환
- steps: [AppRouteStep]      ← GuidanceEngine 호환
- formatted* 속성             ← 기존 MKRoute extension에서 이동

AppRouteStep:
- polyline: MKPolyline       ← 구간 좌표, stepEndCoordinate() 호환
- maneuverType: ManeuverType  ← Kakao guide type 매핑, SF Symbol 아이콘
- instructions: String        ← GuidanceTextBuilder 호환

SearchSuggestion:
- coordinate 포함             ← Apple은 없었음 (2단계 → 1단계로 단순화)
- title/subtitle              ← 기존 테이블 셀 바인딩 패턴 동일

POI:
- toMapItem() → MKMapItem    ← CarPlay CPTrip 호환 브릿지
- from(mapItem:) → POI       ← 네이티브 POI 탭 변환
```

### 의존성
- Phase 0 불필요 (독립적)

### 검증
- [x] 빌드 성공
- [x] AppRoute/AppRouteStep 인스턴스 생성 가능 (struct → init 자동 생성)

---

## 4. Phase 2 — Kakao API DTO

### 목표
Kakao REST API JSON 응답을 디코딩하는 Codable 구조체를 정의한다.

### 작업 목록

| # | 작업 | 파일 | API 엔드포인트 |
|---|------|------|---------------|
| 2-1 | 경로 응답 DTO | `Service/Network/DTO/KakaoDirectionsResponse.swift` | `/v1/directions` |
| 2-2 | 검색 응답 DTO | `Service/Network/DTO/KakaoSearchResponse.swift` | `/v2/local/search/keyword.json` |
| 2-3 | 지오코딩 응답 DTO | `Service/Network/DTO/KakaoGeocodingResponse.swift` | `/v2/local/geo/coord2address.json` |

### 주의사항

```
경로 DTO 핵심 구조:
KakaoDirectionsResponse
└── routes: [KakaoRoute]
    ├── summary: KakaoRouteSummary
    │   ├── distance: Int               (미터)
    │   ├── duration: Int               (초)
    │   └── fare: KakaoFare             (toll, taxi)
    └── sections: [KakaoSection]
        ├── roads: [KakaoRoad]
        │   └── vertexes: [Double]      ⚠ flat 배열 [lng, lat, lng, lat, ...]
        └── guides: [KakaoGuide]
            ├── type: Int               (ManeuverType 매핑)
            ├── guidance: String        (안내 텍스트)
            └── x, y: Double            (lng, lat)

⚠ CodingKeys 주의:
- Kakao JSON은 snake_case (result_code, place_name 등)
- JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase 사용
- 또는 CodingKeys에서 명시적 매핑
```

### 의존성
- Phase 0 불필요 (독립적, Decodable만 사용)

### 검증
- [x] 빌드 성공
- [x] 샘플 JSON 디코딩 Unit Test (권장)

---

## 5. Phase 3 — 서비스 프로토콜

### 목표
ViewModel/Engine이 구체 서비스 대신 프로토콜에 의존하도록 인터페이스를 정의한다.

### 작업 목록

| # | 작업 | 파일 |
|---|------|------|
| 3-1 | 경로 프로토콜 | `Service/Protocol/RouteServiceProtocol.swift` |
| 3-2 | 검색 프로토콜 | `Service/Protocol/SearchServiceProtocol.swift` |
| 3-3 | 지오코딩 프로토콜 | `Service/Protocol/GeocodingServiceProtocol.swift` |

### 프로토콜 시그니처

```swift
// RouteServiceProtocol
func calculateRoutes(
    from: CLLocationCoordinate2D,
    to: CLLocationCoordinate2D,
    priority: RoutePriority
) async throws -> [AppRoute]
func cancelCurrentRequest()

// SearchServiceProtocol
var suggestionsPublisher: CurrentValueSubject<[SearchSuggestion], Never> { get }
var isSearchingPublisher: CurrentValueSubject<Bool, Never> { get }
var errorPublisher: PassthroughSubject<Error, Never> { get }
func updateRegion(_ center: CLLocationCoordinate2D, radius: Int)
func updateQuery(_ fragment: String)
func search(query:center:radius:) async throws -> [POI]
func selectSuggestion(_ suggestion: SearchSuggestion) -> POI
func cancelCurrentSearch()

// GeocodingServiceProtocol
func reverseGeocode(location: CLLocation) async throws -> POI
func geocode(address: String) async throws -> POI
```

### 의존성
- Phase 1 필요 (AppRoute, AppRouteStep, SearchSuggestion, POI 타입 참조)

### 검증
- [x] 빌드 성공

---

## 6. Phase 4 — Kakao 서비스 구현

### 목표
서비스 프로토콜의 Kakao 구현체를 작성한다. 실제 HTTP 호출 + DTO → 앱 모델 변환.

### 작업 목록

| # | 작업 | 파일 | 프로토콜 |
|---|------|------|---------|
| 4-1 | 경로 서비스 | `Service/Route/KakaoRouteService.swift` | RouteServiceProtocol |
| 4-2 | 검색 서비스 | `Service/Search/KakaoSearchService.swift` | SearchServiceProtocol |
| 4-3 | 지오코딩 서비스 | `Service/Search/KakaoGeocodingService.swift` | GeocodingServiceProtocol |

### KakaoRouteService 핵심 로직

```
calculateRoutes(from:to:priority:) 흐름:

1. 좌표 변환
   from: CLLocationCoordinate2D(lat, lng)
   → origin 파라미터: "lng,lat"          ⚠ 순서 반전

2. API 호출
   GET /v1/directions?origin=...&destination=...&priority=RECOMMEND&alternatives=true

3. DTO 디코딩
   KakaoDirectionsResponse → routes[].sections[]

4. vertexes → MKPolyline 변환
   roads[].vertexes: [lng, lat, lng, lat, ...]
   → 2개씩 묶어 CLLocationCoordinate2D(latitude: v[i+1], longitude: v[i])
   → 연속 중복 좌표 제거
   → MKPolyline(coordinates:count:)

5. guides → [AppRouteStep] 변환
   각 guide 좌표에 가장 가까운 polyline 인덱스 찾기 (nearestIndex)
   → guide[i] ~ guide[i+1] 사이 좌표로 구간 MKPolyline 생성
   → guide.type → ManeuverType 매핑
   → AppRouteStep 생성

6. AppRoute 조립
   polyline + steps + summary(distance, duration, fare) → AppRoute

재시도 로직: 기존 RouteService와 동일 (exponential backoff, 최대 3회)
```

### KakaoSearchService 핵심 로직

```
updateQuery(_ fragment:) 흐름:

1. 디바운스 (300ms)
   이전 타이머 취소 → 새 타이머 시작

2. API 호출
   GET /v2/local/search/keyword.json?query=...&x=...&y=...&radius=...

3. DTO → SearchSuggestion 변환
   KakaoPlace → SearchSuggestion
   - place_name → title
   - road_address_name → subtitle
   - x,y → CLLocationCoordinate2D(latitude: y, longitude: x)  ⚠

4. suggestionsPublisher.send(suggestions)

selectSuggestion() 흐름:
   SearchSuggestion → POI (이미 좌표 보유 → 즉시 변환, API 호출 없음)
```

### 의존성
- Phase 0 (KakaoAPIClient), Phase 1 (모델), Phase 2 (DTO), Phase 3 (프로토콜) 모두 필요

### 검증
- [x] 빌드 성공
- [x] 실제 API 호출 테스트 (시뮬레이터에서 검색 → 결과 확인)
- [x] vertexes → MKPolyline 변환 Unit Test
- [x] 좌표 순서 (lng, lat) 변환 정확도 확인

---

## 7. Phase 5 — 코어 엔진 마이그레이션

### 목표
내비게이션 핵심 엔진들의 타입을 MKRoute/MKRoute.Step → AppRoute/AppRouteStep으로 교체한다.

> ⚠ **가장 큰 변경**. 이 Phase부터 기존 코드가 수정되며, 완료 전까지 빌드 실패 가능.

### 작업 목록 (의존성 순서)

| # | 파일 | 주요 변경 | 난이도 |
|---|------|----------|-------|
| 5-1 | `RouteModels.swift` | MKRoute extension 삭제, TransportMode.mkTransportType 제거 | 낮음 |
| 5-2 | `OffRouteDetector.swift` | `configure(with: MKRoute)` → `configure(with: AppRoute)` | 낮음 |
| 5-3 | `GuidanceTextBuilder.swift` | step 파라미터 타입 변경 | 낮음 |
| 5-4 | `GuidanceEngine.swift` | **전면 변경** — 아래 상세 참조 | **높음** |
| 5-5 | `NavigationSessionManager.swift` | NavigationSession { route, destination } 타입 변경 | 중간 |
| 5-6 | `TurnPointPopupService.swift` | `currentRoute: MKRoute?` → `AppRoute?` | 낮음 |
| 5-7 | `VirtualDriveEngine.swift` | `load(route: MKRoute, ...)` → `AppRoute` | 낮음 |

### GuidanceEngine.swift 상세 변경

```
변경 전                              변경 후
─────────────────────────────       ─────────────────────────────
RouteProgress {                     RouteProgress {
  currentStep: MKRoute.Step           currentStep: AppRouteStep
  nextStep: MKRoute.Step?             nextStep: AppRouteStep?
}                                   }

currentStepPublisher:               currentStepPublisher:
  <MKRoute.Step?, Never>              <AppRouteStep?, Never>

currentRoutePublisher:              currentRoutePublisher:
  <MKRoute?, Never>                   <AppRoute?, Never>

route: MKRoute?                     route: AppRoute?
steps: [MKRoute.Step]               steps: [AppRouteStep]

routeService: RouteService          routeService: RouteServiceProtocol

startNavigation(with: MKRoute)      startNavigation(with: AppRoute)

performReroute():                   performReroute():
  routeService.calculateRoutes(       routeService.calculateRoutes(
    from:to:                            from:to:
    transportType:                      priority: .recommend
      transportMode.mkTransportType   )
  )

stepEndCoordinate(                  stepEndCoordinate(
  for: MKRoute.Step                   for: AppRouteStep
)                                   )
  step.polyline.coordinates           step.polyline.coordinates
  ← 동일 (MKPolyline)                ← 동일 (MKPolyline)
```

### 의존성
- Phase 1 (AppRoute, AppRouteStep), Phase 3 (RouteServiceProtocol) 필요
- Phase 4 불필요 (프로토콜에만 의존)

### 검증
- [x] 빌드 성공 (이 시점에서 Phase 6~9 미완료이므로 ViewModel/View에서 컴파일 에러 발생 가능 → Phase 5~9를 연속 작업 권장)
- [x] 기존 OffRouteDetectorTests 업데이트 후 통과
- [x] GuidanceEngine의 step tracking 로직 동작 확인

---

## 8. Phase 6 — ViewModel 마이그레이션

### 목표
ViewModel 계층의 타입을 앱 모델로 교체하고, 서비스 프로토콜에 의존하도록 변경한다.

### 작업 목록

| # | 파일 | 주요 변경 |
|---|------|----------|
| 6-1 | `SearchViewModel.swift` | completions→suggestions, MKMapItem→POI, SearchService→SearchServiceProtocol |
| 6-2 | `RoutePreviewViewModel.swift` | `[MKRoute]`→`[AppRoute]`, RouteService→RouteServiceProtocol |
| 6-3 | `NavigationViewModel.swift` | MKRoute→AppRoute, MKRoute.Step→AppRouteStep |

### SearchViewModel 상세 변경

```
변경 전                                  변경 후
───────────────────────────────         ───────────────────────────────
completions: CVS<[Completion], Never>   suggestions: CVS<[SearchSuggestion], Never>
searchService: SearchService            searchService: SearchServiceProtocol

updateSearchRegion(                     updateSearchRegion(
  _ region: MKCoordinateRegion            center: CLLocationCoordinate2D,
)                                         radius: Int
                                        )

selectCompletion(                       selectSuggestion(
  _ completion: MKLocalSearchCompletion   _ suggestion: SearchSuggestion
) → MKMapItem                           ) → POI

executeSearch() → [MKMapItem]           executeSearch() → [POI]
```

### 의존성
- Phase 1, 3, 5 필요

### 검증
- [x] ViewModel 빌드 성공
- [x] Publisher 타입 정합성 확인

---

## 9. Phase 7 — View 마이그레이션

### 목표
View 계층에서 Apple 타입 참조를 앱 모델로 교체한다. 대부분 파라미터 타입 변경.

### 작업 목록

| # | 파일 | 주요 변경 |
|---|------|----------|
| 7-1 | `SearchViewController.swift` | `[MKLocalSearchCompletion]` → `[SearchSuggestion]`, onSearchResults 콜백 타입 |
| 7-2 | `SearchResultDrawerViewController.swift` | `[MKMapItem]` → `[POI]`, onItemSelected 콜백 타입 |
| 7-3 | `SearchResultCell.swift` | `configure(with: MKMapItem)` → `configure(with: POI)` |
| 7-4 | `POIDetailViewController.swift` | `mapItem: MKMapItem` → `poi: POI`, 프로퍼티 접근 패턴 변경 |
| 7-5 | `RoutePreviewDrawerViewController.swift` | `MKRoute` → `AppRoute`, formatted 속성 동일 |
| 7-6 | `RouteOptionCell.swift` | `configure(with: MKRoute)` → `configure(with: AppRoute)` |
| 7-7 | `SearchResultAnnotation.swift` | `MKMapItem` → `POI` 저장, coordinate/title 매핑 |
| 7-8 | `MapViewController.swift` | showSearchResults/showRoutes 파라미터, onPOISelected 콜백 |

### 프로퍼티 접근 패턴 비교

```
MKMapItem 기반 (변경 전)              POI 기반 (변경 후)
─────────────────────────────        ─────────────────────────────
mapItem.name                         poi.name
mapItem.location.coordinate          poi.coordinate
mapItem.phoneNumber                  poi.phone
mapItem.url                          poi.placeURL
mapItem.address?.fullAddress         poi.fullAddress
(카테고리 없음)                       poi.category         ← 추가 정보
(장소 URL 없음)                      poi.placeURL         ← 카카오맵 링크
```

### MapViewController 특이사항

```
네이티브 POI 탭 (MKMapFeatureAnnotation):
- 기존: MKMapItemRequest → MKMapItem → 직접 사용
- 변경: MKMapItemRequest → MKMapItem → POI.from(mapItem:) → POI 사용
- MKMapView의 built-in POI는 여전히 Apple이 처리 (Kakao와 무관)
```

### 의존성
- Phase 1, 6 필요

### 검증
- [x] 빌드 성공
- [x] 검색 UI: 테이블 셀에 title/subtitle 정상 표시
- [x] POI 상세: 이름, 주소, 전화번호, 카카오맵 링크 표시

---

## 10. Phase 8 — CarPlay 마이그레이션

### 목표
CarPlay 화면에서 사용하는 타입을 앱 모델로 교체한다. CarPlay API가 MKMapItem을 필수로 요구하는 곳에서는 `POI.toMapItem()` 변환을 사용한다.

### 작업 목록

| # | 파일 | 주요 변경 |
|---|------|----------|
| 8-1 | `CarPlaySearchHandler.swift` | `[MKMapItem]`→`[POI]`, `[MKRoute]`→`[AppRoute]`, CPTrip 생성에 `toMapItem()` |
| 8-2 | `CarPlayNavigationHandler.swift` | `MKRoute.Step`→`AppRouteStep`, maneuverType.iconName 활용 |
| 8-3 | `CarPlayMapViewController.swift` | `MKRoute`→`AppRoute` (polyline 동일) |
| 8-4 | `CarPlaySceneDelegate.swift` | 서비스 인스턴스 `KakaoRouteService()`, `KakaoSearchService()` |

### CarPlay MKMapItem 필수 지점

```
CPTrip(origin:destination:) 생성 시:
- origin: MKMapItem.forCurrentLocation()        ← 변경 없음
- destination: poi.toMapItem()                   ← POI → MKMapItem 변환

CPRouteChoice 생성 시:
- route.formattedTravelTime 등 → AppRoute에 동일 속성 존재
- additionalInformationVariants에 톨비/택시비 추가 가능 (Kakao 전용 데이터)

CPManeuver 생성 시:
- step.instructions → 동일 접근
- step.maneuverType.iconName → SF Symbol 이름으로 아이콘 설정
```

### 의존성
- Phase 1, 4, 5, 7 필요

### 검증
- [x] CarPlay 빌드 성공
- [x] CPTrip 생성 정상 동작
- [x] 내비게이션 CPManeuver 아이콘/텍스트 정상 표시

---

## 11. Phase 9 — Coordinator + DataService

### 목표
앱 전체 흐름을 관장하는 AppCoordinator와 DataService의 타입을 교체한다.

### 작업 목록

| # | 파일 | 주요 변경 |
|---|------|----------|
| 9-1 | `AppCoordinator.swift` | 서비스 인스턴스 교체, 모든 flow 콜백 타입 변경 |
| 9-2 | `DataService.swift` | saveSearchHistory/saveFavorite: MKMapItem→POI |

### AppCoordinator 상세 변경

```
프로퍼티:
  searchService: SearchService        → KakaoSearchService (as SearchServiceProtocol)
  routeService: RouteService          → KakaoRouteService (as RouteServiceProtocol)

메서드 시그니처:
  showSearchResults(_ results: [MKMapItem])     → showSearchResults(_ results: [POI])
  showRoutePreview(to mapItem: MKMapItem)       → showRoutePreview(to poi: POI)
  showPOIDetail(_ mapItem: MKMapItem)           → showPOIDetail(_ poi: POI)
  startNavigation(                              → startNavigation(
    with route: MKRoute,                            with route: AppRoute,
    destination: MKMapItem?, ...)                    destination: POI?, ...)
  startVirtualDrive(with route: MKRoute, ...)   → startVirtualDrive(with route: AppRoute, ...)

콜백 타입:
  onSearchResults: (([MKMapItem]) -> Void)?     → (([POI]) -> Void)?
  onItemSelected: ((MKMapItem, Int) -> Void)?   → ((POI, Int) -> Void)?
  onRouteSelected: ((MKRoute) -> Void)?         → ((AppRoute) -> Void)?
  onStartNavigation: ((MKRoute) -> Void)?       → ((AppRoute) -> Void)?
```

### 의존성
- Phase 4~8 모두 필요 (최종 조립 단계)

### 검증
- [x] **전체 빌드 성공** ← 이 시점에서 모든 타입 정합
- [x] 검색 → 결과 드로어 → POI 상세 → 경로 미리보기 → 내비 시작 전체 흐름

---

## 12. Phase 10 — 정리

### 목표
Apple 전용 서비스 파일을 삭제하고, 불필요한 import를 정리한다.

### 작업 목록

| # | 작업 | 파일 |
|---|------|------|
| 10-1 | Apple 경로 서비스 삭제 | `Service/Route/RouteService.swift` |
| 10-2 | Apple 검색 서비스 삭제 | `Service/Search/SearchService.swift` |
| 10-3 | Apple 지오코딩 서비스 삭제 | `Service/Search/GeocodingService.swift` |
| 10-4 | 불필요 import 정리 | 각 파일의 `import MapKit` 중 데이터 API 관련만 제거 |
| 10-5 | 테스트 업데이트 | StubRoute(MKRoute 서브클래스) → AppRoute 인스턴스로 교체 |

### 삭제 판단 기준
- 해당 파일의 타입이 어디에서도 참조되지 않는지 확인
- Xcode에서 "Find in Project"로 `RouteService`, `SearchService`, `GeocodingService` 검색
- 참조 0건이면 삭제, 남아있으면 Apple~ 접두사로 리네임 후 보관

### 검증
- [x] 전체 빌드 성공
- [x] 전체 테스트 통과
- [x] 미사용 코드 경고 없음

---

## 13. Phase 5~9 일괄 작업 전략

Phase 5~9는 타입 변경이 연쇄적으로 전파되므로, **일괄 작업**이 효율적이다.

### 권장 작업 순서 (Phase 5~9 내부)

```
단계 1: 타입 정의 확정 (Phase 5-1)
  RouteModels.swift에서 MKRoute extension 삭제
  → 컴파일 에러 위치가 모든 MKRoute.formatted* 사용처를 알려줌

단계 2: 바텀업 교체 (Phase 5-2 ~ 5-7)
  하위 모듈부터 타입 교체:
  OffRouteDetector → GuidanceTextBuilder → GuidanceEngine
  → NavigationSessionManager → TurnPointPopupService → VirtualDriveEngine

단계 3: ViewModel 교체 (Phase 6)
  Engine 변경에 맞춰 ViewModel 타입 교체

단계 4: View 교체 (Phase 7)
  ViewModel 변경에 맞춰 View 타입 교체

단계 5: CarPlay 교체 (Phase 8)
  독립적이지만 Phase 5 완료 후 진행

단계 6: 조립 (Phase 9)
  AppCoordinator에서 서비스 인스턴스 교체 + 콜백 타입 통일
```

### 컴파일 에러 활용 팁

```
전략: "의도적 컴파일 에러 체이싱"

1. AppRoute/AppRouteStep으로 코어 타입 변경
2. ⌘+B (빌드) → 컴파일 에러 목록 확인
3. 에러 위치 = 아직 변경하지 않은 사용처
4. 에러를 하나씩 해결하며 진행
5. 에러 0개 = 마이그레이션 완료

이 방식이 가능한 이유:
- MKRoute과 AppRoute는 호환 불가능한 다른 타입
- 컴파일러가 모든 사용처를 자동으로 찾아줌
- 런타임 에러 없이 타입 안전성 보장
```

---

## 14. 파일 변경 요약

```
신규 파일 (16개):
  Service/Network/         KakaoAPIConfig, KakaoAPIClient, KakaoAPIError
  Service/Network/DTO/     KakaoDirectionsResponse, KakaoSearchResponse, KakaoGeocodingResponse
  Service/Protocol/        RouteServiceProtocol, SearchServiceProtocol, GeocodingServiceProtocol
  Service/Route/           KakaoRouteService
  Service/Search/          KakaoSearchService, KakaoGeocodingService
  Model/                   AppRoute, AppRouteStep, SearchSuggestion, POI

수정 파일 (~24개):
  Service/ (7)    RouteModels, GuidanceEngine, OffRouteDetector, GuidanceTextBuilder,
                  NavigationSessionManager, TurnPointPopupService, VirtualDriveEngine
  ViewModel/ (3)  SearchVM, RoutePreviewVM, NavigationVM
  View/ (8)       SearchVC, SearchResultDrawerVC, SearchResultCell, POIDetailVC,
                  RoutePreviewDrawerVC, RouteOptionCell, SearchResultAnnotation, MapVC
  CarPlay/ (4)    CarPlaySearchHandler, CarPlayNavigationHandler, CarPlayMapVC, CarPlaySceneDelegate
  Other/ (2)      AppCoordinator, DataService

삭제 파일 (3개):
  Service/Route/   RouteService.swift
  Service/Search/  SearchService.swift, GeocodingService.swift
```

---

## 15. 리스크 및 대응

| 리스크 | 영향 | 대응 |
|--------|------|------|
| API 키 미발급/만료 | Phase 4~9 테스트 불가 | 개발 시작 전 Kakao Developers 계정 생성 + 앱 등록 + REST API 키 발급 선행 |
| 경로 vertexes 변환 오류 (좌표 순서) | 경로가 지도에 잘못 표시됨 | Unit Test로 좌표 변환 검증, 시뮬레이터에서 시각적 확인 |
| Phase 5~9 중간 빌드 실패 | 개발 중 테스트 불가 | 일괄 작업으로 최대한 빠르게 전환, 중간 커밋 없이 Phase 9까지 진행 |
| Kakao API rate limit 초과 | 검색 동작 중단 | 디바운스 300ms, 에러 핸들링에서 사용자 알림 |
| 보행자 경로 미지원 | 도보 모드 사용 불가 | UI에서 비활성 처리 + "자동차 경로만 지원" 안내 |
| CarPlay CPTrip MKMapItem 필수 | POI 직접 사용 불가 | `POI.toMapItem()` 브릿지 메서드 |
