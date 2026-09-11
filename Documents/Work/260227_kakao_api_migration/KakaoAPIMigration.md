# Kakao API 마이그레이션 — 개발 계획서

## 1. 개요

### 배경
현재 경로 탐색(`MKDirections`), POI 검색(`MKLocalSearch`), 지오코딩(`MKLocalSearch`)에 Apple MapKit API를 사용 중이다. 한국에서의 POI 데이터 품질, 경로 정확도, 실시간 교통 반영을 개선하기 위해 **Kakao REST API**로 데이터 소스를 전환한다.

### 목표
- 경로 탐색, POI 검색, 지오코딩을 **Kakao REST API**로 교체
- **지도 표시(MKMapView)는 그대로 유지** — Apple MapKit으로 렌더링
- 서비스 프로토콜 도입으로 테스트 용이성 확보
- CarPlay 호환성 유지

### 핵심 과제
`MKRoute`, `MKRoute.Step`, `MKLocalSearchCompletion`은 직접 생성이 불가능한 Apple 전용 타입이다. Kakao API 응답 데이터로 이 타입들을 생성할 수 없으므로, **앱 자체 모델**(AppRoute, AppRouteStep, SearchSuggestion)로 교체해야 한다.

### 관련 문서
- [PRD.md](../PRD.md) — 7.3 경로 미리보기, 7.4 네비게이션 안내
- [TechSpec.md](../TechSpec.md) — 2.1 경로 탐색, 2.2 장소 검색, 3.1 경로 이탈 감지
- [Architecture.md](../Architecture.md) — 서비스 레이어, 데이터 흐름

---

## 2. 현재 구현 vs 목표 비교

### 데이터 소스 변경

```
현재 (Apple MapKit)                      목표 (Kakao REST API + Apple MapKit 표시)
┌──────────────────────┐                ┌──────────────────────┐
│   Apple MapKit API   │                │  Kakao REST API      │
│  ┌────────────────┐  │                │  ┌────────────────┐  │
│  │ MKDirections   │──┼─→ [MKRoute]    │  │ /v1/directions │──┼─→ [AppRoute]
│  │ MKLocalSearch  │──┼─→ [MKMapItem]  │  │ /v2/local/...  │──┼─→ [POI]
│  │ MKLocalSearch- │  │                │  │ /v2/local/geo/ │──┼─→ [POI]
│  │  Completer     │──┼─→ [Completion] │  │  (debounce)    │──┼─→ [SearchSuggestion]
│  └────────────────┘  │                │  └────────────────┘  │
└──────────────────────┘                └──────────────────────┘
         │                                        │
         ▼                                        ▼
┌──────────────────────┐                ┌──────────────────────┐
│  Apple MapKit 표시    │                │  Apple MapKit 표시    │  ← 동일
│  MKMapView           │                │  MKMapView           │
│  MKPolyline          │                │  MKPolyline          │
│  MKAnnotation        │                │  MKAnnotation        │
└──────────────────────┘                └──────────────────────┘
```

### 타입 대체 요약

| Apple 타입 (직접 생성 불가) | 앱 자체 모델 | 비고 |
|---|---|---|
| `MKRoute` | `AppRoute` | polyline은 MKPolyline으로 유지 |
| `MKRoute.Step` | `AppRouteStep` | Kakao guide → ManeuverType 매핑 |
| `MKLocalSearchCompletion` | `SearchSuggestion` | 디바운스 키워드 검색으로 대체 |
| `MKMapItem` (생성 가능) | `POI` | `toMapItem()` 변환 메서드 제공 |
| `MKDirections.ETAResponse` | (삭제) | AppRoute.expectedTravelTime으로 대체 |
| `MKDirectionsTransportType` | (삭제) | Kakao는 자동차 전용 |

---

## 3. Kakao API 상세

### 3.1 API 인증

```
모든 요청에 HTTP 헤더 필요:
Authorization: KakaoAK {REST_API_KEY}

API 키 발급: https://openapi.sk.com 또는 https://developers.kakao.com
Info.plist에 KAKAO_REST_API_KEY로 저장
```

### 3.2 경로 탐색 — Kakao Mobility Directions API

```
엔드포인트: GET https://apis-navi.kakaomobility.com/v1/directions

주요 파라미터:
- origin: "127.0276,37.4979"          (lng,lat — 주의: Apple과 순서 반대)
- destination: "126.9780,37.5665"     (lng,lat)
- priority: RECOMMEND | TIME | DISTANCE
- alternatives: true                  (대안 경로 포함)
- car_fuel: GASOLINE | DIESEL | LPG   (연료 타입)
- car_hipass: true | false             (하이패스 여부)

응답 구조:
{
  "routes": [
    {
      "result_code": 0,
      "result_msg": "성공",
      "summary": {
        "origin": { "name": "출발지", "x": 127.0, "y": 37.5 },
        "destination": { "name": "도착지", "x": 126.9, "y": 37.5 },
        "distance": 12500,           // 미터
        "duration": 1800,            // 초
        "fare": { "taxi": 15000, "toll": 2400 },
        "bbox": { ... }
      },
      "sections": [
        {
          "distance": 12500,
          "duration": 1800,
          "roads": [
            {
              "name": "테헤란로",
              "distance": 500,
              "duration": 60,
              "vertexes": [127.0, 37.5, 127.001, 37.501, ...]
              // ⚠ flat 배열: [lng, lat, lng, lat, ...]
            }
          ],
          "guides": [
            {
              "name": "강남역사거리",
              "x": 127.0276, "y": 37.4979,
              "distance": 300,
              "duration": 36,
              "type": 2,              // 가이드 타입 코드
              "guidance": "우회전하세요"
            }
          ]
        }
      ]
    }
  ]
}

무료 한도: 10,000건/일
유료 단가: ~10원/건 (프로모션, 2026.12까지)
```

### 3.3 POI 검색 — Kakao Developers Local API

```
엔드포인트: GET https://dapi.kakao.com/v2/local/search/keyword.json

주요 파라미터:
- query: "강남역 카페"
- x: 127.0276                         (lng — 검색 중심)
- y: 37.4979                          (lat — 검색 중심)
- radius: 20000                       (미터, 최대 20km)
- size: 15                            (결과 수, 최대 45)
- sort: accuracy | distance
- page: 1                             (페이지네이션)

응답 구조:
{
  "meta": {
    "total_count": 120,
    "pageable_count": 45,
    "is_end": false
  },
  "documents": [
    {
      "id": "8137634",
      "place_name": "스타벅스 강남역점",
      "category_name": "음식점 > 카페",
      "category_group_code": "CE7",
      "phone": "02-1234-5678",
      "address_name": "서울 강남구 역삼동 123",
      "road_address_name": "서울 강남구 테헤란로 123",
      "x": "127.0276",                // longitude (문자열)
      "y": "37.4979",                 // latitude (문자열)
      "place_url": "http://place.map.kakao.com/8137634",
      "distance": "150"               // 미터 (문자열, 중심 좌표 기준)
    }
  ]
}

무료 한도: 100,000건/일
유료 단가: 2원/건
```

### 3.4 지오코딩 — Kakao Developers Local API

```
정방향 (주소 → 좌표):
GET https://dapi.kakao.com/v2/local/search/address.json?query=서울 강남구 테헤란로 123

역방향 (좌표 → 주소):
GET https://dapi.kakao.com/v2/local/geo/coord2address.json?x=127.0276&y=37.4979

역방향 응답:
{
  "documents": [
    {
      "road_address": {
        "address_name": "서울 강남구 테헤란로 123",
        "road_name": "테헤란로",
        "building_no": "123"
      },
      "address": {
        "address_name": "서울 강남구 역삼동 123",
        "region_1depth_name": "서울",
        "region_2depth_name": "강남구",
        "region_3depth_name": "역삼동"
      }
    }
  ]
}

무료 한도: 검색 API와 통합 (월 3,000,000건)
```

### 3.5 Apple vs Kakao 비교

| 항목 | Apple MapKit | Kakao REST API |
|------|-------------|----------------|
| 경로 무료 한도 | 제한 없음 (throttle 있음) | 10,000건/일 |
| POI 검색 무료 한도 | 제한 없음 | 100,000건/일 |
| 한국 POI 품질 | 보통 | **우수** (카카오맵 데이터) |
| 실시간 교통 | 있음 | **있음** (TMAP 급 교통 데이터) |
| 톨비/택시비 | 미제공 | **제공** |
| 자동완성 | MKLocalSearchCompleter (전용 API) | **없음** (키워드 검색으로 대체) |
| 보행자 경로 | 있음 (.walking) | **없음** (자동차 전용) |
| 좌표 순서 | (lat, lng) | **(lng, lat)** ⚠ |
| 인증 | 불필요 | API Key 필요 |
| 네트워크 | 시스템 최적화 | 직접 HTTP 호출 |
| 오프라인 | 불가 | 불가 |

---

## 4. 아키텍처 변경

### 4.1 레이어 변경 범위

```
┌──────────────────────────────────────────────────────────┐
│                      App Layer                           │  변경 없음
├──────────────────────────────────────────────────────────┤
│                   Coordinator Layer                      │  타입 변경
│  AppCoordinator: MKRoute→AppRoute, MKMapItem→POI        │  (MKRoute, MKMapItem
│  CarPlaySceneDelegate: 서비스 인스턴스 변경                │   → AppRoute, POI)
├──────────────────────────────────────────────────────────┤
│                    View Layer (UIKit)                     │  타입 변경
│  SearchVC: MKLocalSearchCompletion → SearchSuggestion    │
│  SearchResultDrawerVC: MKMapItem → POI                   │
│  POIDetailVC: MKMapItem → POI                           │
│  RoutePreviewDrawerVC: MKRoute → AppRoute               │
│  MapVC: 표시 로직 유지 (MKPolyline, MKAnnotation)         │
├──────────────────────────────────────────────────────────┤
│                  ViewModel Layer                          │  타입 변경
│  SearchVM: completions → suggestions, MKMapItem → POI    │
│  RoutePreviewVM: [MKRoute] → [AppRoute]                  │
│  NavigationVM: MKRoute → AppRoute                       │
├──────────────────────────────────────────────────────────┤
│                   Service Layer                          │  ★ 핵심 변경
│  RouteService → KakaoRouteService (RouteServiceProtocol) │
│  SearchService → KakaoSearchService (SearchServiceProtocol)│
│  GeocodingService → KakaoGeocodingService                │
│  GuidanceEngine: MKRoute.Step → AppRouteStep             │
│  OffRouteDetector: MKRoute → AppRoute                    │
│  NavigationSessionManager: 세션 타입 변경                  │
│  + 신규: KakaoAPIClient, KakaoAPIConfig, KakaoAPIError    │
├──────────────────────────────────────────────────────────┤
│                    Data Layer                             │  일부 변경
│  DataService: MKMapItem → POI (저장 시)                   │
├──────────────────────────────────────────────────────────┤
│               Model Layer (신규 추가)                     │  ★ 신규
│  AppRoute │ AppRouteStep │ ManeuverType                  │
│  SearchSuggestion │ POI                                  │
├──────────────────────────────────────────────────────────┤
│                 Apple Frameworks                         │  표시 전용
│  MapKit (MKMapView, MKPolyline, MKAnnotation만 사용)      │
│  CoreLocation │ AVFoundation │ CarPlay │ Combine         │
└──────────────────────────────────────────────────────────┘
```

### 4.2 서비스 프로토콜 도입

```
┌─────────────────────────────────────────────────────────────┐
│                    서비스 프로토콜                             │
│                                                             │
│  RouteServiceProtocol ──────── KakaoRouteService            │
│  SearchServiceProtocol ─────── KakaoSearchService           │
│  GeocodingServiceProtocol ──── KakaoGeocodingService        │
│                                                             │
│  ViewModel / Engine은 프로토콜에만 의존                       │
│  → 테스트 시 Mock 교체 가능                                   │
│  → 향후 다른 API 제공자로 교체 가능                            │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 검색 자동완성 패턴 변경

```
현재 (Apple MKLocalSearchCompleter):
┌──────────────┐      ┌────────────────────┐      ┌─────────────┐
│ 사용자 입력    │─────→│ MKLocalSearchCompleter│─────→│ [Completion]│
│ "강남"        │      │ (Apple 전용 자동완성) │      │ title/subtitle│
└──────────────┘      └────────────────────┘      └──────┬──────┘
                                                         │ 선택
                                                         ▼
                                                  ┌─────────────┐
                                                  │ MKLocalSearch│──→ [MKMapItem]
                                                  └─────────────┘

목표 (Kakao 디바운스 키워드 검색):
┌──────────────┐  300ms  ┌─────────────────────┐      ┌────────────────┐
│ 사용자 입력    │─debounce→│ Kakao Keyword Search│─────→│ [SearchSuggestion]│
│ "강남"        │         │ /v2/local/search/   │      │ 이미 좌표 포함     │
└──────────────┘         │ keyword.json        │      │ 즉시 사용 가능     │
                         └─────────────────────┘      └────────────────┘

차이점:
- Apple: 2단계 (자동완성 → 선택 시 검색)
- Kakao: 1단계 (검색이 곧 자동완성, 결과에 좌표 포함)
- Kakao 방식이 더 단순하지만 API 호출이 더 많음 → 디바운스로 최적화
```

---

## 5. 신규 모델 설계

### 5.1 AppRoute — MKRoute 대체

```swift
struct AppRoute: Sendable {
    let polyline: MKPolyline              // Kakao vertexes → MKPolyline 변환
    let steps: [AppRouteStep]
    let distance: CLLocationDistance       // 미터
    let expectedTravelTime: TimeInterval   // 초
    let name: String                       // 경로 이름 ("추천", "최단 시간" 등)
    let tollFare: Int                      // 톨비 (원) — Kakao 전용
    let taxiFare: Int                      // 택시비 (원) — Kakao 전용
    let priority: RoutePriority

    // 기존 MKRoute extension에서 이동한 computed properties
    var formattedDistance: String           // "2.5km" / "350m"
    var formattedTravelTime: String        // "15분" / "1시간 20분"
    var estimatedArrivalTime: Date         // Date() + expectedTravelTime
    var formattedArrivalTime: String       // "14:30 도착"
    var boundingMapRect: MKMapRect         // polyline.boundingMapRect
}

enum RoutePriority: String, Sendable {
    case recommend = "RECOMMEND"
    case time = "TIME"
    case distance = "DISTANCE"
}
```

**MKRoute와의 호환성:**
- `polyline` → 동일 타입 (`MKPolyline`), 기존 지도 오버레이 코드 그대로 사용
- `steps` → `AppRouteStep` 배열, `step.polyline.coordinates` 접근 패턴 동일
- `distance`, `expectedTravelTime` → 동일 타입, 동일 단위
- formatted 속성 → 기존 MKRoute extension에서 그대로 복사

### 5.2 AppRouteStep — MKRoute.Step 대체

```swift
struct AppRouteStep: Sendable {
    let instructions: String              // "우회전하세요", "직진하세요"
    let distance: CLLocationDistance       // 구간 거리 (미터)
    let duration: TimeInterval             // 구간 소요 시간 (초)
    let polyline: MKPolyline              // 구간 좌표 (좌표 추출용)
    let maneuverType: ManeuverType        // 회전 타입 (Kakao guide type 매핑)
    let roadName: String?                 // 도로명
}
```

**Kakao Guide Type → ManeuverType 매핑:**

```
Kakao type │ ManeuverType     │ iconName              │ 안내 텍스트
───────────┼──────────────────┼───────────────────────┼────────────────
0          │ .straight        │ arrow.up              │ 직진하세요
1          │ .turnLeft        │ arrow.turn.up.left    │ 좌회전하세요
2          │ .turnRight       │ arrow.turn.up.right   │ 우회전하세요
3          │ .uTurn           │ arrow.uturn.left      │ 유턴하세요
5          │ .leftOnRamp      │ arrow.turn.up.left    │ 좌측 진입로
6          │ .rightOnRamp     │ arrow.turn.up.right   │ 우측 진입로
7          │ .straightOnHwy   │ arrow.up              │ 직진 (고속도로)
8          │ .leftAtJunction  │ arrow.turn.up.left    │ 좌측 분기점
9          │ .rightAtJunction │ arrow.turn.up.right   │ 우측 분기점
100        │ .destination     │ flag.fill             │ 목적지 도착
101        │ .departure       │ arrow.up              │ 출발
```

### 5.3 SearchSuggestion — MKLocalSearchCompletion 대체

```swift
struct SearchSuggestion: Sendable {
    let id: String                        // Kakao place ID
    let title: String                     // place_name (≈ completion.title)
    let subtitle: String                  // road_address_name (≈ completion.subtitle)
    let coordinate: CLLocationCoordinate2D // ⭐ Apple 대비 추가 — 이미 좌표 보유
    let category: String?                 // category_name ("음식점 > 카페")
    let phone: String?
    let placeURL: URL?
}
```

### 5.4 POI — MKMapItem 대체 (대부분의 사용처)

```swift
struct POI: Sendable {
    let id: String?                       // Kakao place ID
    let name: String                      // ≈ mapItem.name
    let coordinate: CLLocationCoordinate2D // ≈ mapItem.location.coordinate
    let address: String?                  // 지번 주소
    let roadAddress: String?             // 도로명 주소
    let category: String?               // Kakao 카테고리 ("음식점 > 카페")
    let phone: String?                  // ≈ mapItem.phoneNumber
    let placeURL: URL?                  // ≈ mapItem.url

    /// CarPlay CPTrip 생성 시 필요 (CarPlay API는 MKMapItem 필수)
    func toMapItem() -> MKMapItem

    var shortAddress: String? { roadAddress ?? address }
    var fullAddress: String?  // "도로명 (지번)"
}
```

**MKMapItem을 직접 사용하지 않는 이유:**
- `MKMapItem`은 생성 가능하지만, `.address` 프로퍼티를 직접 설정할 수 없음
- Kakao는 `category`, `place_url` 등 더 풍부한 데이터 제공
- POI 모델이 앱 전반에서 더 명확한 의미를 가짐

**MKMapItem이 여전히 필요한 곳:**
- `CPTrip(origin:destination:)` — CarPlay API가 MKMapItem 필수
- `MKMapItem.forCurrentLocation()` — CarPlay 출발지
- MapKit 네이티브 POI 탭 (`MKMapFeatureAnnotation` → `MKMapItemRequest`)

---

## 6. 서비스 프로토콜 설계

### 6.1 RouteServiceProtocol

```swift
protocol RouteServiceProtocol {
    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        priority: RoutePriority
    ) async throws -> [AppRoute]

    func cancelCurrentRequest()
}
```

**기존 RouteService와 차이:**
- `transportType: MKDirectionsTransportType` → `priority: RoutePriority`
- `calculateETA()` 삭제 (AppRoute.expectedTravelTime으로 대체)
- 반환 타입: `[MKRoute]` → `[AppRoute]`

### 6.2 SearchServiceProtocol

```swift
protocol SearchServiceProtocol {
    var suggestionsPublisher: CurrentValueSubject<[SearchSuggestion], Never> { get }
    var isSearchingPublisher: CurrentValueSubject<Bool, Never> { get }
    var errorPublisher: PassthroughSubject<Error, Never> { get }

    func updateRegion(_ center: CLLocationCoordinate2D, radius: Int)
    func updateQuery(_ fragment: String)
    func search(query: String, center: CLLocationCoordinate2D?, radius: Int?) async throws -> [POI]
    func selectSuggestion(_ suggestion: SearchSuggestion) -> POI
    func cancelCurrentSearch()
}
```

**기존 SearchService와 차이:**
- `completionsPublisher` → `suggestionsPublisher` (타입 변경)
- `updateRegion(_ region: MKCoordinateRegion)` → `updateRegion(_ center:, radius:)`
- `search(for completion: MKLocalSearchCompletion)` → `selectSuggestion()` (즉시 반환)
- `search(query:region:)` → `search(query:center:radius:)` → `[POI]`

### 6.3 GeocodingServiceProtocol

```swift
protocol GeocodingServiceProtocol {
    func reverseGeocode(location: CLLocation) async throws -> POI
    func geocode(address: String) async throws -> POI
}
```

---

## 7. Kakao API 인프라

### 7.1 HTTP 클라이언트

```
파일: Service/Network/KakaoAPIClient.swift

역할: 모든 Kakao REST API 호출의 공통 HTTP 클라이언트

주요 메서드:
- request<T: Decodable>(url:queryItems:responseType:) → async throws T

동작:
1. URLComponents로 URL + 쿼리 파라미터 조합
2. Authorization: KakaoAK {key} 헤더 추가
3. URLSession.data(for:) 호출
4. HTTP 상태 코드 검사 (200번대 외 → KakaoAPIError.httpError)
5. JSONDecoder로 디코딩 (실패 → KakaoAPIError.decodingError)

싱글턴: KakaoAPIClient.shared
타임아웃: request 10초, resource 30초
```

### 7.2 API 설정

```
파일: Service/Network/KakaoAPIConfig.swift

API Key: Info.plist의 KAKAO_REST_API_KEY에서 로드
BaseURL:
- mobility: https://apis-navi.kakaomobility.com (경로)
- local: https://dapi.kakao.com (검색/지오코딩)
```

### 7.3 에러 타입

```
파일: Service/Network/KakaoAPIError.swift

- invalidResponse: 서버 응답이 올바르지 않습니다
- httpError(statusCode, data): 서버 오류 (코드: N)
- noResults: 결과를 찾을 수 없습니다
- invalidCoordinates: 유효하지 않은 좌표입니다
- rateLimited: 요청 횟수가 초과되었습니다
```

---

## 8. 핵심 변환 로직

### 8.1 Kakao Vertexes → MKPolyline

Kakao 경로 응답의 `roads[].vertexes`는 `[lng, lat, lng, lat, ...]` 형태의 flat 배열이다. 이를 MKPolyline으로 변환한다.

```
Kakao 응답 (roads):
  road[0].vertexes: [127.0, 37.5, 127.001, 37.501, 127.002, 37.502]
  road[1].vertexes: [127.002, 37.502, 127.003, 37.503]
  ...

변환 과정:
1. 모든 sections → roads → vertexes를 순서대로 이터레이션
2. 2개씩 묶어서 CLLocationCoordinate2D 생성
   ⚠ 주의: Kakao는 (lng, lat) → Apple은 (lat, lng) 순서
   vertexes[i] = longitude, vertexes[i+1] = latitude
3. 연속 중복 좌표 제거 (인접 road 경계에서 발생)
4. MKPolyline(coordinates:count:) 생성

결과:
- 전체 경로를 나타내는 하나의 MKPolyline
- 기존 MapViewController.addOverlay() 그대로 사용 가능
```

### 8.2 Kakao Guides → [AppRouteStep]

```
Kakao 응답 (guides):
  guide[0]: { type: 101, guidance: "출발", x: 127.0, y: 37.5, distance: 0 }
  guide[1]: { type: 2,   guidance: "우회전하세요", x: 127.001, y: 37.501, distance: 300 }
  guide[2]: { type: 0,   guidance: "직진하세요", x: 127.003, y: 37.503, distance: 1200 }
  guide[3]: { type: 100, guidance: "목적지", x: 127.005, y: 37.505, distance: 0 }

변환 과정:
1. 각 guide의 좌표 → CLLocationCoordinate2D(latitude: y, longitude: x)
2. guide[i] ~ guide[i+1] 사이의 전체 polyline에서 해당 구간 추출
   → nearestIndex() 알고리즘으로 guide 좌표에 가장 가까운 polyline 인덱스 찾기
   → 두 인덱스 사이의 좌표들로 구간 MKPolyline 생성
3. guide.type → ManeuverType 매핑
4. guide.guidance → instructions (비어있으면 ManeuverType 기본 텍스트 사용)
5. AppRouteStep 생성

결과:
- step.polyline.coordinates로 구간 좌표 접근 가능 (기존 GuidanceEngine 호환)
- step.instructions로 안내 텍스트 접근 가능 (기존 GuidanceTextBuilder 호환)
- step.maneuverType.iconName으로 SF Symbol 아이콘 직접 사용
```

### 8.3 POI ↔ MKMapItem 변환

```swift
// POI → MKMapItem (CarPlay용)
func toMapItem() -> MKMapItem {
    let item = MKMapItem(
        location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
        address: nil
    )
    item.name = name
    item.phoneNumber = phone
    item.url = placeURL
    return item
}

// MKMapItem → POI (네이티브 POI 탭 시)
// MapKit MKMapFeatureAnnotation 탭 → MKMapItemRequest → MKMapItem → POI
static func from(mapItem: MKMapItem) -> POI {
    POI(
        id: nil,
        name: mapItem.name ?? "",
        coordinate: mapItem.location.coordinate,
        address: nil,
        roadAddress: mapItem.address?.fullAddress,
        category: nil,
        phone: mapItem.phoneNumber,
        placeURL: mapItem.url
    )
}
```

---

## 9. 마이그레이션 대상 파일

### 9.1 신규 파일 (16개)

```
Service/Network/
├── KakaoAPIClient.swift                     # 공유 HTTP 클라이언트
├── KakaoAPIConfig.swift                     # API Key + Base URL
├── KakaoAPIError.swift                      # 에러 타입
└── DTO/
    ├── KakaoDirectionsResponse.swift        # 경로 API 응답 DTO
    ├── KakaoSearchResponse.swift            # 검색 API 응답 DTO
    └── KakaoGeocodingResponse.swift         # 지오코딩 API 응답 DTO

Service/Protocol/
├── RouteServiceProtocol.swift
├── SearchServiceProtocol.swift
└── GeocodingServiceProtocol.swift

Service/Route/
└── KakaoRouteService.swift                  # 경로 탐색 Kakao 구현

Service/Search/
├── KakaoSearchService.swift                 # POI 검색 Kakao 구현
└── KakaoGeocodingService.swift              # 지오코딩 Kakao 구현

Model/
├── AppRoute.swift                           # MKRoute 대체
├── AppRouteStep.swift                       # MKRoute.Step 대체 + ManeuverType
├── SearchSuggestion.swift                   # MKLocalSearchCompletion 대체
└── POI.swift                                # MKMapItem 대체
```

### 9.2 수정 파일

#### Service Layer (7개) — 가장 큰 변경

| 파일 | 변경 내용 |
|------|----------|
| `RouteModels.swift` | MKRoute extension 삭제 (AppRoute로 이동), TransportMode.mkTransportType 제거 |
| `GuidanceEngine.swift` | MKRoute→AppRoute, MKRoute.Step→AppRouteStep, RouteProgress 타입 변경, routeService→프로토콜, reroute 호출 변경 |
| `OffRouteDetector.swift` | `configure(with: MKRoute)` → `configure(with: AppRoute)` |
| `GuidanceTextBuilder.swift` | `buildInstructionFromStep(_ step: MKRoute.Step)` → `AppRouteStep` |
| `NavigationSessionManager.swift` | NavigationSession { route: MKRoute, destination: MKMapItem } → { AppRoute, POI } |
| `TurnPointPopupService.swift` | `currentRoute: MKRoute?` → `AppRoute?` |
| `VirtualDriveEngine.swift` | `load(route: MKRoute, ...)` → `AppRoute` |

#### ViewModel Layer (3개)

| 파일 | 변경 내용 |
|------|----------|
| `SearchViewModel.swift` | completions→suggestions, MKMapItem→POI, searchService→프로토콜 |
| `RoutePreviewViewModel.swift` | `[MKRoute]`→`[AppRoute]`, routeService→프로토콜 |
| `NavigationViewModel.swift` | MKRoute→AppRoute, MKRoute.Step→AppRouteStep |

#### View Layer (8개)

| 파일 | 변경 내용 |
|------|----------|
| `SearchViewController.swift` | MKLocalSearchCompletion→SearchSuggestion, onSearchResults 타입 |
| `SearchResultDrawerViewController.swift` | `[MKMapItem]`→`[POI]`, onItemSelected 타입 |
| `SearchResultCell.swift` | `configure(with: MKMapItem)` → `configure(with: POI)` |
| `POIDetailViewController.swift` | mapItem→poi, onRouteTapped 타입 |
| `RoutePreviewDrawerViewController.swift` | MKRoute→AppRoute, onRoutesChanged/onStartNavigation 타입 |
| `RouteOptionCell.swift` | `configure(with: MKRoute)` → `configure(with: AppRoute)` |
| `SearchResultAnnotation.swift` | MKMapItem→POI |
| `MapViewController.swift` | showSearchResults/showRoutes 타입, onPOISelected 타입 |

#### CarPlay Layer (4개)

| 파일 | 변경 내용 |
|------|----------|
| `CarPlaySearchHandler.swift` | MKMapItem→POI, MKRoute→AppRoute, CPTrip에 poi.toMapItem() |
| `CarPlayNavigationHandler.swift` | MKRoute.Step→AppRouteStep, maneuverType.iconName 활용 |
| `CarPlayMapViewController.swift` | MKRoute→AppRoute (polyline 동일) |
| `CarPlaySceneDelegate.swift` | 서비스 인스턴스 변경, CPTrip 생성 시 toMapItem() |

#### Coordinator + Data (2개)

| 파일 | 변경 내용 |
|------|----------|
| `AppCoordinator.swift` | 서비스 인스턴스 교체, 모든 flow 콜백 타입 변경 |
| `DataService.swift` | saveSearchHistory/saveFavorite: MKMapItem→POI |

#### 정리 (3개)

| 파일 | 변경 내용 |
|------|----------|
| `RouteService.swift` | 삭제 또는 Apple~ 접두사로 보관 |
| `SearchService.swift` | 삭제 또는 Apple~ 접두사로 보관 |
| `GeocodingService.swift` | 삭제 또는 Apple~ 접두사로 보관 |

---

## 10. 구현 순서

Phase 0~4는 신규 파일만 생성 (기존 코드에 영향 없음).
Phase 5~10은 기존 파일 수정 (한 번에 전환).

```
Phase 0  [신규] API 인프라 ─────────────── KakaoAPIClient, Config, Error
Phase 1  [신규] 앱 모델 ───────────────── AppRoute, AppRouteStep, SearchSuggestion, POI
Phase 2  [신규] DTO ──────────────────── KakaoDirectionsResponse, SearchResponse, GeocodingResponse
Phase 3  [신규] 프로토콜 ─────────────── RouteServiceProtocol, SearchServiceProtocol, GeocodingServiceProtocol
Phase 4  [신규] Kakao 서비스 ──────────── KakaoRouteService, KakaoSearchService, KakaoGeocodingService
─────────────────── 여기까지 기존 코드 변경 없음 ────────────────────
Phase 5  [수정] 코어 엔진 ──────────────── GuidanceEngine, OffRouteDetector, SessionManager 등 (7개)
Phase 6  [수정] ViewModel ─────────────── SearchVM, RoutePreviewVM, NavigationVM (3개)
Phase 7  [수정] View ──────────────────── SearchVC, DrawerVC, POIDetailVC 등 (8개)
Phase 8  [수정] CarPlay ───────────────── SearchHandler, NavHandler, MapVC, SceneDelegate (4개)
Phase 9  [수정] Coordinator + Data ────── AppCoordinator, DataService (2개)
Phase 10 [정리] 기존 서비스 삭제 ────────── RouteService, SearchService, GeocodingService
```

---

## 11. 제한사항 및 주의사항

### 11.1 보행자 경로 미지원
Kakao Mobility Directions API는 **자동차 전용**이다.
- `TransportMode.walking` UI에서 비활성 처리 (disabled + "미지원" 안내)
- 향후 Kakao 보행자 API 추가 시 활성화

### 11.2 좌표 순서 주의
```
Apple CoreLocation:  CLLocationCoordinate2D(latitude, longitude)
Kakao API 파라미터:  origin=longitude,latitude  ← ⚠ 반대

DTO 변환 시 반드시:
- Kakao "x" = longitude, "y" = latitude
- CLLocationCoordinate2D(latitude: y, longitude: x)
```

### 11.3 API Key 보안
- 개발: Info.plist에 직접 저장
- 프로덕션 권장: xcconfig 파일 + .gitignore로 키 분리
- 또는 서버 프록시를 통해 실제 키 은닉

### 11.4 네이티브 POI 탭
MKMapView의 built-in POI (`MKMapFeatureAnnotation`)는 Apple MapKit 고유 기능이다.
- `MKMapItemRequest` → `MKMapItem` 반환
- 받은 `MKMapItem`을 `POI.from(mapItem:)` 로 변환하여 앱 흐름에 통합
- 이 기능은 Kakao와 무관하게 동작

### 11.5 API Rate Limiting
- 키워드 검색 디바운스: 300ms (타이핑마다 API 호출 방지)
- 경로 재탐색 디바운스: 10초 (기존 로직 유지)
- 무료 한도 초과 시 KakaoAPIError.rateLimited → 사용자에게 알림

### 11.6 테스트 마이그레이션
- 기존 `StubRoute` (MKRoute 서브클래스) → `AppRoute` 인스턴스로 교체
- AppRoute는 struct이므로 서브클래싱 없이 직접 생성 가능 (테스트 더 쉬워짐)

---

## 12. 검증 방법

### 12.1 빌드 검증

```bash
cd Navigation
xcodebuild build \
  -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet
```

### 12.2 기능 테스트

| # | 시나리오 | 검증 항목 |
|---|---------|----------|
| 1 | 검색바 입력 "강남역" | 300ms 후 자동완성 목록 표시 (SearchSuggestion) |
| 2 | 자동완성 항목 선택 | 검색 결과 드로어 + 지도 마커 표시 (POI → SearchResultAnnotation) |
| 3 | 검색 결과 항목 탭 | POI 상세 시트 표시 (이름, 주소, 전화, 웹사이트) |
| 4 | "경로" 버튼 탭 | 경로 미리보기 드로어 (다중 AppRoute, 톨비/택시비 표시) |
| 5 | 경로 선택 → 지도 | MKPolyline 오버레이 표시 (주행 경로 + 대안 경로) |
| 6 | "안내 시작" 탭 | 내비게이션 화면 (GuidanceEngine with AppRouteStep) |
| 7 | 경로 이탈 시뮬레이션 | 재탐색 → 새 AppRoute 적용 → 지도 업데이트 |
| 8 | 회전 지점 접근 | 팝업 표시 + 음성 안내 (AppRouteStep.instructions) |
| 9 | 목적지 도착 | 도착 안내 + 내비 종료 |
| 10 | 즐겨찾기/최근검색 탭 | 경로 미리보기 드로어 표시 |
| 11 | CarPlay 검색 | Kakao 검색 → CPListItem 표시 |
| 12 | CarPlay 경로 선택 | AppRoute → CPTrip (poi.toMapItem() 변환) → 안내 시작 |
| 13 | 가상 주행 | AppRoute.polyline 기반 시뮬레이션 정상 동작 |
| 14 | GPX 재생 중 내비 | GuidanceEngine이 AppRouteStep 기반으로 정상 안내 |

### 12.3 단위 테스트

```
기존 테스트 수정:
- OffRouteDetectorTests: MKRoute 서브클래스 → AppRoute 인스턴스
- GuidanceTextBuilderTests: MKRoute.Step → AppRouteStep
- NavigationSessionManagerTests: MKRoute → AppRoute, MKMapItem → POI

신규 테스트:
- KakaoRouteServiceTests: vertexes→MKPolyline 변환 정확도
- KakaoSearchServiceTests: 디바운스 동작, POI 변환
- AppRouteTests: formatted 속성 정확도
- ManeuverTypeTests: Kakao type 매핑 검증
```

---

## 13. 파일 변경 요약

```
Navigation/Navigation/
├── Model/
│   ├── AppRoute.swift                  ← 신규
│   ├── AppRouteStep.swift              ← 신규 (+ ManeuverType)
│   ├── SearchSuggestion.swift          ← 신규
│   └── POI.swift                       ← 신규
│
├── Service/
│   ├── Network/
│   │   ├── KakaoAPIClient.swift        ← 신규
│   │   ├── KakaoAPIConfig.swift        ← 신규
│   │   ├── KakaoAPIError.swift         ← 신규
│   │   └── DTO/
│   │       ├── KakaoDirectionsResponse.swift  ← 신규
│   │       ├── KakaoSearchResponse.swift      ← 신규
│   │       └── KakaoGeocodingResponse.swift   ← 신규
│   │
│   ├── Protocol/
│   │   ├── RouteServiceProtocol.swift  ← 신규
│   │   ├── SearchServiceProtocol.swift ← 신규
│   │   └── GeocodingServiceProtocol.swift ← 신규
│   │
│   ├── Route/
│   │   ├── KakaoRouteService.swift     ← 신규
│   │   ├── RouteService.swift          ← 삭제 (Apple 구현)
│   │   └── RouteModels.swift           ← 수정 (MKRoute extension 삭제)
│   │
│   ├── Search/
│   │   ├── KakaoSearchService.swift    ← 신규
│   │   ├── KakaoGeocodingService.swift ← 신규
│   │   ├── SearchService.swift         ← 삭제 (Apple 구현)
│   │   └── GeocodingService.swift      ← 삭제 (Apple 구현)
│   │
│   ├── Guidance/
│   │   ├── GuidanceEngine.swift        ← 수정 (MKRoute→AppRoute 전체)
│   │   └── OffRouteDetector.swift      ← 수정 (시그니처)
│   │
│   ├── Voice/
│   │   └── GuidanceTextBuilder.swift   ← 수정 (step 타입)
│   │
│   ├── CarPlay/
│   │   └── NavigationSessionManager.swift ← 수정 (세션 타입)
│   │
│   ├── TurnPointPopup/
│   │   └── TurnPointPopupService.swift ← 수정 (route 타입)
│   │
│   ├── VirtualDrive/
│   │   └── VirtualDriveEngine.swift    ← 수정 (route 타입)
│   │
│   └── Data/
│       └── DataService.swift           ← 수정 (MKMapItem→POI)
│
├── Feature/
│   ├── Search/
│   │   ├── SearchViewController.swift         ← 수정
│   │   ├── SearchResultDrawerViewController.swift ← 수정
│   │   └── SearchResultCell.swift             ← 수정
│   │
│   ├── POIDetail/
│   │   └── POIDetailViewController.swift      ← 수정
│   │
│   ├── RoutePreview/
│   │   ├── RoutePreviewDrawerViewController.swift ← 수정
│   │   ├── RoutePreviewViewModel.swift        ← 수정
│   │   └── RouteOptionCell.swift              ← 수정
│   │
│   ├── Navigation/
│   │   ├── NavigationViewModel.swift          ← 수정
│   │   └── NavigationViewController.swift     ← 수정 (minor)
│   │
│   └── CarPlay/
│       ├── CarPlaySearchHandler.swift         ← 수정
│       ├── CarPlayNavigationHandler.swift     ← 수정
│       └── CarPlayMapViewController.swift     ← 수정
│
├── Map/
│   ├── MapViewController.swift                ← 수정
│   └── Annotation/
│       └── SearchResultAnnotation.swift       ← 수정
│
├── Coordinator/
│   └── AppCoordinator.swift                   ← 수정
│
└── App/
    └── CarPlaySceneDelegate.swift             ← 수정

합계: 신규 16개 │ 수정 ~24개 │ 삭제 3개
```
