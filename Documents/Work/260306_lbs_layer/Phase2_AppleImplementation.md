# Phase 2: Apple 구현체 전환

## 목표
기존 SearchService, RouteService, GeocodingService를 Phase 1의 프로토콜에 맞게
**AppleSearchService, AppleRouteService, AppleGeocodingService**로 래핑한다.
기능 변경 없이 동일한 동작을 유지하면서, 내부에서 Apple ↔ 앱 모델 변환을 처리한다.

---

## 2-1. 변환 유틸리티 (Apple ↔ App Model)

### 파일 위치
```
Navigation/Service/LBS/Apple/AppleModelConverter.swift
```

### Place ↔ MKMapItem
```swift
enum AppleModelConverter {

    // MKMapItem → Place
    static func place(from mapItem: MKMapItem) -> Place {
        Place(
            name: mapItem.name,
            coordinate: mapItem.location.coordinate,
            address: mapItem.address?.fullAddress,
            phoneNumber: mapItem.phoneNumber,
            category: mapItem.pointOfInterestCategory?.rawValue,
            providerRawData: mapItem
        )
    }

    // Place → MKMapItem (지도 레이어에서 필요 시)
    static func mapItem(from place: Place) -> MKMapItem {
        // providerRawData가 MKMapItem이면 그대로 반환
        if let original = place.providerRawData as? MKMapItem {
            return original
        }
        let item = MKMapItem(
            location: CLLocation(latitude: place.coordinate.latitude,
                                 longitude: place.coordinate.longitude),
            address: nil
        )
        item.name = place.name
        return item
    }
}
```

### Route ↔ MKRoute
```swift
extension AppleModelConverter {

    // MKRoute → Route
    static func route(from mkRoute: MKRoute) -> Route {
        Route(
            id: UUID().uuidString,
            distance: mkRoute.distance,
            expectedTravelTime: mkRoute.expectedTravelTime,
            name: mkRoute.name,
            steps: mkRoute.steps.map { routeStep(from: $0) },
            polylineCoordinates: mkRoute.polyline.coordinates,
            transportMode: mkRoute.transportType == .walking ? .walking : .automobile
        )
    }

    // MKRoute.Step → RouteStep
    static func routeStep(from mkStep: MKRoute.Step) -> RouteStep {
        RouteStep(
            instructions: mkStep.instructions,
            distance: mkStep.distance,
            polylineCoordinates: mkStep.polyline.coordinates
        )
    }
}
```

### SearchCompletion ↔ MKLocalSearchCompletion
```swift
extension AppleModelConverter {

    // MKLocalSearchCompletion → SearchCompletion
    static func searchCompletion(from mkCompletion: MKLocalSearchCompletion) -> SearchCompletion {
        SearchCompletion(
            id: "\(mkCompletion.title)_\(mkCompletion.subtitle)",
            title: mkCompletion.title,
            subtitle: mkCompletion.subtitle,
            highlightRanges: nil   // Apple은 titleHighlightRanges 제공하지만 NSValue 형태
        )
    }
}
```

**주의:** `search(for: SearchCompletion)`에서 원본 `MKLocalSearchCompletion`이 필요하므로,
AppleSearchService 내부에서 `[SearchCompletion.id: MKLocalSearchCompletion]` 매핑을 유지한다.

---

## 2-2. AppleSearchService

### 파일 위치
```
Navigation/Service/LBS/Apple/AppleSearchService.swift
```

### 핵심 변경점
| 기존 (SearchService) | 변경 (AppleSearchService) |
|---|---|
| `completionsPublisher: [MKLocalSearchCompletion]` | `completionsPublisher: [SearchCompletion]` |
| `search(for: MKLocalSearchCompletion) -> [MKMapItem]` | `search(for: SearchCompletion) -> [Place]` |
| `search(query:) -> [MKMapItem]` | `search(query:) -> [Place]` |

### 구현 개요
```swift
final class AppleSearchService: NSObject, SearchProviding {
    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    // 내부: 원본 매핑 보존
    private var completionMap: [String: MKLocalSearchCompletion] = [:]
    private let completer = MKLocalSearchCompleter()
    private let queryCompleter = MKLocalSearchCompleter()
    private var currentSearch: MKLocalSearch?

    // MKLocalSearchCompleterDelegate에서:
    // 1. MKLocalSearchCompletion → SearchCompletion 변환
    // 2. completionMap에 id → 원본 저장
    // 3. completionsPublisher.send(변환된 배열)

    func search(for completion: SearchCompletion) async throws -> [Place] {
        // completionMap에서 원본 MKLocalSearchCompletion 조회
        guard let mkCompletion = completionMap[completion.id] else {
            throw SearchError.completionNotFound
        }
        let request = MKLocalSearch.Request(mkCompletion)
        // ... 기존 로직 동일
        // response.mapItems → [Place] 변환하여 반환
    }
}
```

---

## 2-3. AppleRouteService

### 파일 위치
```
Navigation/Service/LBS/Apple/AppleRouteService.swift
```

### 핵심 변경점
| 기존 (RouteService) | 변경 (AppleRouteService) |
|---|---|
| `calculateRoutes(..., transportType: MKDirectionsTransportType) -> [MKRoute]` | `calculateRoutes(..., transportMode: TransportMode) -> [Route]` |
| `calculateETA() -> MKDirections.ETAResponse` | `calculateETA() -> TimeInterval` |

### 구현 개요
```swift
final class AppleRouteService: RouteProviding {
    private var currentDirections: MKDirections?
    private let maxRetryCount = 3

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        // 기존 MKDirections 로직 동일
        let mkRoutes = try await performWithRetry(request: request)
        return mkRoutes.map { AppleModelConverter.route(from: $0) }
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        // 기존 로직 동일
        let response = try await directions.calculateETA()
        return response.expectedTravelTime
    }
}
```

---

## 2-4. AppleGeocodingService

### 파일 위치
```
Navigation/Service/LBS/Apple/AppleGeocodingService.swift
```

### 핵심 변경점
| 기존 (GeocodingService) | 변경 (AppleGeocodingService) |
|---|---|
| `reverseGeocode() -> MKMapItem` | `reverseGeocode() -> Place` |
| `geocode() -> MKMapItem` | `geocode() -> Place` |

---

## 2-5. 기존 서비스 파일 처리

| 파일 | 처리 |
|---|---|
| `Service/Search/SearchService.swift` | 삭제 (AppleSearchService로 대체) |
| `Service/Route/RouteService.swift` | 삭제 (AppleRouteService로 대체) |
| `Service/Route/RouteModels.swift` | TransportMode는 LBS/Model/로 이동, MKRoute extension 삭제 |
| `Service/Search/GeocodingService.swift` | 삭제 (AppleGeocodingService로 대체) |

**에러 타입 통합:**
```swift
// Navigation/Service/LBS/Model/LBSError.swift
enum LBSError: Error, LocalizedError {
    case noRoutesFound
    case networkError(Error)
    case cancelled
    case noResults
    case completionNotFound
    case quotaExceeded       // Phase 4에서 사용

    var errorDescription: String? { ... }
}
```

---

## 2-6. Route → MKPolyline 변환 (지도 레이어용)

MapViewController에서 overlay를 그릴 때 MKPolyline이 필요하므로,
**변환은 View 레이어에서만** 수행한다.

```swift
// Navigation/Map/Extension/Route+MapKit.swift
import MapKit

extension Route {
    var mkPolyline: MKPolyline {
        MKPolyline(coordinates: polylineCoordinates, count: polylineCoordinates.count)
    }
}

extension Place {
    var mkMapItem: MKMapItem {
        AppleModelConverter.mapItem(from: self)
    }
}
```

---

## 검증 항목

| # | 검증 내용 | 방법 |
|---|---|---|
| V2-1 | AppleSearchService가 SearchProviding 프로토콜을 완전히 준수하는가 | 컴파일 확인 |
| V2-2 | AppleRouteService가 RouteProviding 프로토콜을 완전히 준수하는가 | 컴파일 확인 |
| V2-3 | AppleGeocodingService가 GeocodingProviding 프로토콜을 완전히 준수하는가 | 컴파일 확인 |
| V2-4 | AppleModelConverter의 MKRoute → Route 변환이 정확한가 | 단위 테스트: distance, travelTime, step 수, polyline 좌표 수 비교 |
| V2-5 | AppleModelConverter의 MKMapItem → Place → MKMapItem 라운드트립이 정보 손실 없는가 | 단위 테스트 |
| V2-6 | SearchCompletion → MKLocalSearchCompletion 매핑이 search 호출까지 유지되는가 | AppleSearchService 내부 completionMap 테스트 |
| V2-7 | Route.formattedDistance 등 포맷 유틸이 기존 MKRoute extension과 동일 출력인가 | 동일 입력값으로 비교 테스트 |
| V2-8 | Route.mkPolyline으로 MapViewController overlay 정상 표시되는가 | UI 확인 (시뮬레이터) |
| V2-9 | 기존 RouteServiceError, GeocodingError가 LBSError로 통합 후 에러 핸들링 정상인가 | catch 구문 확인 |
| V2-10 | 기존 서비스 파일 삭제 후 빌드 에러 없는가 | `xcodebuild build` (Phase 3 완료 후) |

**주의:** V2-10은 Phase 3 완료 후 소비자 코드도 전환되어야 통과 가능.
Phase 2 단독으로는 기존 서비스를 삭제하지 않고 **병행 유지**한 뒤, Phase 3 완료 후 삭제한다.
