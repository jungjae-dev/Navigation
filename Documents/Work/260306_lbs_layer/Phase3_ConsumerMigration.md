# Phase 3: 소비자 코드 마이그레이션

## 목표
서비스 소비자(ViewModel, Engine, Coordinator, CarPlay)가 Apple 타입 대신
**앱 고유 모델(Place, Route, RouteStep)과 프로토콜(SearchProviding, RouteProviding)**을 사용하도록 전환한다.

---

## 마이그레이션 순서

안전한 전환을 위해 **의존성 방향의 역순** (말단 → 핵심)으로 진행:

```
Step 1: 모델/유틸 (GuidanceTextBuilder, RouteModels)
Step 2: 엔진 (GuidanceEngine, OffRouteDetector, VirtualDriveEngine)
Step 3: ViewModel (SearchViewModel, RoutePreviewViewModel, NavigationViewModel)
Step 4: Coordinator & CarPlay
Step 5: 기존 서비스 삭제 & 정리
```

---

## Step 3-1: 모델/유틸 전환

### GuidanceTextBuilder.swift
| 변경 | 내용 |
|---|---|
| `buildInstructionFromStep(_ step: MKRoute.Step)` | `buildInstructionFromStep(_ step: RouteStep)` |
| `import MapKit` | `import CoreLocation` (CLLocationDistance만 필요) |

```swift
// Before
static func buildInstructionFromStep(_ step: MKRoute.Step) -> String {
    let instruction = step.instructions
    ...
}

// After
static func buildInstructionFromStep(_ step: RouteStep) -> String {
    let instruction = step.instructions
    ...
}
```

### RouteModels.swift → TransportMode 분리
- `TransportMode` enum을 `LBS/Model/TransportMode.swift`로 이동
- `mkTransportType` computed property는 `Apple/AppleRouteService.swift` 내부로 이동
- MKRoute extension (formattedDistance 등)은 `Route` extension으로 이전 (Phase 1에서 이미 정의)
- 기존 `RouteModels.swift` 삭제

### RouteProgress 구조체
```swift
// Before (GuidanceEngine.swift 내부)
struct RouteProgress {
    ...
    let currentStep: MKRoute.Step
    let nextStep: MKRoute.Step?
}

// After
struct RouteProgress {
    ...
    let currentStep: RouteStep
    let nextStep: RouteStep?
}
```

---

## Step 3-2: 엔진 전환

### GuidanceEngine.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `routeService` 타입 | `RouteService` | `RouteProviding` |
| `currentRoutePublisher` | `CurrentValueSubject<MKRoute?, Never>` | `CurrentValueSubject<Route?, Never>` |
| `currentStepPublisher` | `CurrentValueSubject<MKRoute.Step?, Never>` | `CurrentValueSubject<RouteStep?, Never>` |
| `route` 프로퍼티 | `MKRoute?` | `Route?` |
| `steps` 프로퍼티 | `[MKRoute.Step]` | `[RouteStep]` |
| `startNavigation(with:)` | `MKRoute` 파라미터 | `Route` 파라미터 |
| `stepEndCoordinate(for:)` | `MKRoute.Step` 파라미터 | `RouteStep` 파라미터 |
| `performReroute()` | `routeService.calculateRoutes(transportType:)` | `routeService.calculateRoutes(transportMode:)` |

**polyline 좌표 접근 변경:**
```swift
// Before
let coords = step.polyline.coordinates
destination = coords.last

// After
destination = step.polylineCoordinates.last
```

### OffRouteDetector.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `configure(with:)` | `MKRoute` 파라미터 | `Route` 파라미터 |
| `routePolyline` | `MKPolyline?` | 삭제, `routeCoordinates: [CLLocationCoordinate2D]` 사용 |

```swift
// Before
func configure(with route: MKRoute) {
    routePolyline = route.polyline
}

// After
func configure(with route: Route) {
    routeCoordinates = route.polylineCoordinates
}
```

**DistanceCalculator 변경:**
`nearestPointOnPolyline`이 MKPolyline을 받는 경우, `[CLLocationCoordinate2D]` 오버로드 추가:
```swift
static func nearestPointOnPolyline(
    _ coordinates: [CLLocationCoordinate2D],
    from: CLLocationCoordinate2D,
    searchRange: ClosedRange<Int>
) -> (distance: CLLocationDistance, segmentIndex: Int)
```

### VirtualDriveEngine.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `load(route:)` | `MKRoute` 파라미터 | `Route` 파라미터 |

```swift
// Before
func load(route: MKRoute, transportMode: TransportMode = .automobile) {
    routeCoordinates = route.polyline.coordinates

// After
func load(route: Route) {
    routeCoordinates = route.polylineCoordinates
    baseSpeedMPS = route.transportMode == .walking ? ... : ...
```

---

## Step 3-3: ViewModel 전환

### SearchViewModel.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `completions` | `CurrentValueSubject<[MKLocalSearchCompletion], Never>` | `CurrentValueSubject<[SearchCompletion], Never>` |
| `queryCompletions` | `CurrentValueSubject<[MKLocalSearchCompletion], Never>` | `CurrentValueSubject<[SearchCompletion], Never>` |
| `searchService` | `SearchService` | `SearchProviding` |
| `selectCompletion()` | `MKLocalSearchCompletion` → `[MKMapItem]?` | `SearchCompletion` → `[Place]?` |
| `executeSearch()` | `-> [MKMapItem]?` | `-> [Place]?` |
| `selectRecentSearch()` | `-> [MKMapItem]` | `-> [Place]` |

### RoutePreviewViewModel.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `routes` | `CurrentValueSubject<[MKRoute], Never>` | `CurrentValueSubject<[Route], Never>` |
| `routeService` | `RouteService` | `RouteProviding` |
| `getSelectedRoute()` | `-> MKRoute?` | `-> Route?` |
| `calculateRoutes()` | `routeService.calculateRoutes(transportType:)` | `routeService.calculateRoutes(transportMode:)` |

### NavigationViewModel.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `route` | `MKRoute?` | `Route?` |
| `startNavigation(with:)` | `MKRoute` 파라미터 | `Route` 파라미터 |
| `updateManeuver(with:)` | `MKRoute.Step` 파라미터 | `RouteStep` 파라미터 |

---

## Step 3-4: Coordinator & CarPlay 전환

### AppCoordinator.swift

**주요 변경점:**
| 항목 | Before | After |
|---|---|---|
| `searchService` | `SearchService` | `SearchProviding` (LBSServiceProvider.shared.search) |
| `routeService` | `RouteService` | `RouteProviding` (LBSServiceProvider.shared.route) |
| `showSearchResults()` | `[MKMapItem]` | `[Place]` |
| `showRoutePreview(to:)` | `MKMapItem` | `Place` |
| `showPOIDetail()` | `MKMapItem` | `Place` |
| `startNavigation(with:)` | `MKRoute, MKMapItem` | `Route, Place` |

**DI 방식 변경:**
```swift
// Before
init(window: UIWindow) {
    self.searchService = SearchService()
    self.routeService = RouteService()
}

// After
init(window: UIWindow) {
    let provider = LBSServiceProvider.shared
    self.searchService = provider.search
    self.routeService = provider.route
}
```

**지도 레이어 경계에서의 변환:**
```swift
// showSearchResults — Place → MKMapItem (MapViewController용)
private func showSearchResults(_ results: [Place]) {
    let mapItems = results.map { $0.mkMapItem }
    mapViewController.showSearchResults(mapItems)
    ...
}

// startNavigation — Route → MKPolyline (MapViewController용)
navMapVC.showSingleRoute(route.mkPolyline)  // 또는 Route 전달 후 내부 변환
```

### NavigationSessionManager.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `NavigationSession.route` | `MKRoute` | `Route` |
| `NavigationSession.destination` | `MKMapItem` | `Place` |
| `routeService` | `RouteService()` | `LBSServiceProvider.shared.route` |
| `startNavigation(route:destination:)` | MKRoute, MKMapItem | Route, Place |

### CarPlaySearchHandler.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `onRouteSelected` | `(MKRoute, MKMapItem)` | `(Route, Place)` |
| `onRoutePreview` | `(MKRoute)` | `(Route)` |
| `routeService` | `RouteService` | `RouteProviding` |
| `searchService` | `SearchService` | `SearchProviding` |
| `searchResults` | `[MKMapItem]` | `[Place]` |
| `showTripPreviews()` | 내부에서 Place → MKMapItem 변환하여 CPTrip 생성 |

### CarPlayNavigationHandler.swift

**변경점:**
| 항목 | Before | After |
|---|---|---|
| `buildManeuver(from:)` | `MKRoute.Step` 파라미터 | `RouteStep` 파라미터 |
| `updateRouteInformation()` | `RouteProgress.nextStep`가 이미 RouteStep | 변경 없음 (Step 3-2에서 해결) |

### CarPlayFavoritesHandler.swift
- `MKMapItem` → `Place` 변환 후 콜백

### CarPlaySceneDelegate.swift
- 내부 서비스 참조를 `LBSServiceProvider.shared`에서 가져오도록 변경

---

## Step 3-5: View 레이어 변경

### MapViewController.swift
- `showSearchResults([MKMapItem])` → `showSearchResults([Place])` 또는 내부에서 변환
- `showRoutes([MKRoute], selectedIndex:)` → `showRoutes([Route], selectedIndex:)`
  - 내부에서 `route.mkPolyline`으로 overlay 생성
- `showSingleRoute(MKRoute)` → `showSingleRoute(Route)`
- `onPOISelected: (MKMapItem)` → `onPOISelected: (Place)`

### SearchResultDrawerViewController.swift
- `updateResults([MKMapItem])` → `updateResults([Place])`
- 셀 표시: `place.name`, `place.address`

### POIDetailViewController.swift
- `init(mapItem: MKMapItem)` → `init(place: Place)`
- `update(with: MKMapItem)` → `update(with: Place)`

### SearchViewController.swift
- `MKLocalSearchCompletion` → `SearchCompletion`

### RoutePreviewDrawerViewController.swift
- `onRoutesChanged: ([MKRoute], Int)` → `onRoutesChanged: ([Route], Int)`
- `onStartNavigation: (MKRoute, TransportMode)` → `onStartNavigation: (Route, TransportMode)`

### RouteOptionCell.swift
- `configure(with: MKRoute)` → `configure(with: Route)`

### SearchResultCell.swift
- `configure(with: MKMapItem)` → `configure(with: Place)` (또는 내부 변환)

### SearchResultAnnotation.swift
- `init(mapItem: MKMapItem)` → `init(place: Place)` + 내부에서 coordinate 매핑

---

## Step 3-6: 기존 서비스 삭제 & 정리

Phase 2-3 완료 후 삭제 대상:
| 파일 | 이유 |
|---|---|
| `Service/Search/SearchService.swift` | AppleSearchService로 대체 |
| `Service/Route/RouteService.swift` | AppleRouteService로 대체 |
| `Service/Route/RouteModels.swift` | TransportMode 분리 완료, MKRoute extension 삭제 |
| `Service/Search/GeocodingService.swift` | AppleGeocodingService로 대체 |

---

## 검증 항목

| # | 검증 내용 | 방법 |
|---|---|---|
| V3-1 | 전체 프로젝트 빌드 성공 | `xcodebuild build` |
| V3-2 | 검색 → 자동완성 → 결과 표시 → POI 상세 플로우 정상 | 시뮬레이터 수동 테스트 |
| V3-3 | 경로 탐색 → 미리보기 → 경로 옵션 전환 플로우 정상 | 시뮬레이터 수동 테스트 |
| V3-4 | 네비게이션 시작 → 안내 → 도착 플로우 정상 | VirtualDrive로 테스트 |
| V3-5 | 경로 이탈 → 재탐색 플로우 정상 | VirtualDrive + 위치 오버라이드 |
| V3-6 | CarPlay 검색 → 경로 → 네비게이션 플로우 정상 | CarPlay 시뮬레이터 |
| V3-7 | 즐겨찾기/최근검색 → 경로 미리보기 플로우 정상 | 시뮬레이터 수동 테스트 |
| V3-8 | GuidanceEngine voice 안내 텍스트 정상 | VirtualDrive 주행 중 음성 확인 |
| V3-9 | 지도 overlay (경로 선) 정상 표시 | 시뮬레이터 시각 확인 |
| V3-10 | 지도 annotation (검색 마커, 목적지 핀) 정상 표시 | 시뮬레이터 시각 확인 |
| V3-11 | `import MapKit` 참조가 Service/LBS/Apple/ 와 Map/ 레이어에만 남아있는가 | Grep 검증: `grep -r "import MapKit" --include="*.swift"` |
| V3-12 | 기존 서비스 파일 삭제 후 빌드 성공 | `xcodebuild build` |
| V3-13 | 기존 단위 테스트 통과 | `xcodebuild test` |
