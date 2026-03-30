# Phase 1: 기반 구조 — 앱 모델 / 프로토콜 / DI 컨테이너

## 목표
Apple MapKit 타입(MKRoute, MKMapItem 등)에 직접 의존하는 구조를 탈피하여,
**Provider-agnostic한 앱 고유 모델**과 **서비스 프로토콜**을 정의한다.

---

## 1-1. 앱 고유 모델 정의

### 파일 위치
```
Navigation/Service/LBS/Model/
├── Place.swift
├── Route.swift
├── RouteStep.swift
└── SearchCompletion.swift
```

### Place (MKMapItem 대체)
```swift
import CoreLocation

struct Place: Sendable {
    let name: String?
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let phoneNumber: String?
    let category: String?
    let providerRawData: Any?   // 원본 데이터 보존 (MKMapItem, Kakao JSON 등)
}
```

**사용처 (현재 MKMapItem 직접 사용 중인 파일):**
| 파일 | 용도 |
|---|---|
| SearchViewModel.swift | 검색 결과 반환 |
| SearchResultDrawerViewController.swift | 결과 리스트 표시 |
| POIDetailViewController.swift | POI 상세 정보 |
| CarPlaySearchHandler.swift | CarPlay 검색 결과 |
| CarPlayFavoritesHandler.swift | 즐겨찾기 → 목적지 |
| AppCoordinator.swift | 경로 미리보기/네비게이션 시작 |
| NavigationSessionManager.swift | 세션 목적지 저장 |
| DataService.swift | 검색 히스토리/즐겨찾기 저장 |

### Route (MKRoute 대체)
```swift
import CoreLocation

struct Route: Sendable {
    let id: String                                    // 고유 식별자
    let distance: CLLocationDistance                   // 총 거리 (m)
    let expectedTravelTime: TimeInterval              // 예상 소요시간 (s)
    let name: String                                  // 경로명
    let steps: [RouteStep]                            // 안내 지점
    let polylineCoordinates: [CLLocationCoordinate2D] // 전체 경로 좌표
    let transportMode: TransportMode
}
```

**포맷팅 유틸 (기존 MKRoute extension 이전):**
```swift
extension Route {
    var formattedDistance: String { ... }
    var formattedTravelTime: String { ... }
    var estimatedArrivalTime: Date { ... }
    var formattedArrivalTime: String { ... }
}
```

**사용처 (현재 MKRoute 직접 사용 중인 파일):**
| 파일 | 용도 |
|---|---|
| RoutePreviewViewModel.swift | 경로 목록 / 선택 |
| RoutePreviewDrawerViewController.swift | 경로 옵션 표시 |
| RouteOptionCell.swift | 경로 셀 표시 |
| NavigationViewModel.swift | 주행 중 현재 경로 |
| GuidanceEngine.swift | 경로 진행 추적 |
| OffRouteDetector.swift | 이탈 감지 (polyline) |
| VirtualDriveEngine.swift | 가상 주행 (polyline) |
| MapViewController.swift | 경로 overlay |
| CarPlayNavigationHandler.swift | CarPlay 네비게이션 |
| CarPlaySearchHandler.swift | CarPlay 경로 미리보기 |
| CarPlayMapViewController.swift | CarPlay 지도 overlay |
| NavigationSessionManager.swift | 세션 경로 저장 |
| AppCoordinator.swift | 네비게이션 시작 |

### RouteStep (MKRoute.Step 대체)
```swift
import CoreLocation

struct RouteStep: Sendable {
    let instructions: String
    let distance: CLLocationDistance
    let polylineCoordinates: [CLLocationCoordinate2D]
}
```

**사용처:**
| 파일 | 용도 |
|---|---|
| GuidanceEngine.swift | RouteProgress, step 추적 |
| NavigationViewModel.swift | 안내 텍스트 |
| CarPlayNavigationHandler.swift | CPManeuver 생성 |
| GuidanceTextBuilder.swift | 안내 텍스트 빌드 |

### SearchCompletion (MKLocalSearchCompletion 대체)
```swift
struct SearchCompletion: Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let highlightRanges: [Range<String.Index>]?  // 검색어 하이라이트 (선택)
}
```

**사용처:**
| 파일 | 용도 |
|---|---|
| SearchService.swift | 자동완성 결과 publish |
| SearchViewModel.swift | completions binding |
| SearchViewController.swift | 자동완성 셀 표시 |

---

## 1-2. 서비스 프로토콜 정의

### 파일 위치
```
Navigation/Service/LBS/Protocol/
├── SearchProviding.swift
├── RouteProviding.swift
└── GeocodingProviding.swift
```

### SearchProviding
```swift
import Combine
import MapKit   // MKCoordinateRegion 참조 (지도 레이어 공용)

protocol SearchProviding: AnyObject {
    var completionsPublisher: CurrentValueSubject<[SearchCompletion], Never> { get }
    var queryCompletionsPublisher: CurrentValueSubject<[SearchCompletion], Never> { get }
    var isSearchingPublisher: CurrentValueSubject<Bool, Never> { get }
    var errorPublisher: PassthroughSubject<Error, Never> { get }

    func updateRegion(_ region: MKCoordinateRegion)
    func updateQuery(_ fragment: String)
    func search(for completion: SearchCompletion) async throws -> [Place]
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place]
    func cancelCurrentSearch()
}
```

### RouteProviding
```swift
import CoreLocation

protocol RouteProviding: AnyObject {
    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route]

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval

    func cancelCurrentRequest()
}
```

### GeocodingProviding
```swift
import CoreLocation

protocol GeocodingProviding: AnyObject {
    func reverseGeocode(location: CLLocation) async throws -> Place
    func geocode(address: String) async throws -> Place
}
```

---

## 1-3. ServiceProvider (DI 컨테이너)

### 파일 위치
```
Navigation/Service/LBS/ServiceProvider.swift
```

### 구현
```swift
enum LBSProviderType: String, CaseIterable {
    case apple
    case kakao
}

final class LBSServiceProvider {
    static let shared = LBSServiceProvider()

    private(set) var search: SearchProviding
    private(set) var route: RouteProviding
    private(set) var geocoding: GeocodingProviding

    let providerType: LBSProviderType

    private init() {
        // UserDefaults 또는 설정에서 읽기, 기본값 apple
        let savedType = UserDefaults.standard.string(forKey: "lbs_provider")
            .flatMap(LBSProviderType.init(rawValue:)) ?? .apple

        self.providerType = savedType

        switch savedType {
        case .apple:
            search = AppleSearchService()
            route = AppleRouteService()
            geocoding = AppleGeocodingService()
        case .kakao:
            fatalError("Phase 4에서 구현")
        }
    }

    /// 런타임 provider 전환 (앱 재시작 없이)
    func switchProvider(to type: LBSProviderType) {
        // Phase 5에서 구현
    }
}
```

---

## 1-4. 디렉토리 구조 (최종)

```
Navigation/Service/LBS/
├── Model/
│   ├── Place.swift
│   ├── Route.swift
│   ├── RouteStep.swift
│   └── SearchCompletion.swift
├── Protocol/
│   ├── SearchProviding.swift
│   ├── RouteProviding.swift
│   └── GeocodingProviding.swift
├── ServiceProvider.swift
├── Apple/                     ← Phase 2
│   ├── AppleSearchService.swift
│   ├── AppleRouteService.swift
│   └── AppleGeocodingService.swift
└── Kakao/                     ← Phase 4
    ├── KakaoSearchService.swift
    ├── KakaoRouteService.swift
    └── KakaoGeocodingService.swift
```

---

## 검증 항목

| # | 검증 내용 | 방법 |
|---|---|---|
| V1-1 | 모든 모델 파일이 컴파일 되는가 | `xcodebuild build` |
| V1-2 | Route.formattedDistance 등 포맷 유틸이 기존과 동일한 출력을 하는가 | 단위 테스트 |
| V1-3 | 프로토콜이 기존 서비스의 public 인터페이스를 빠짐없이 커버하는가 | 코드 리뷰 (SearchService, RouteService, GeocodingService의 public 메서드 대조) |
| V1-4 | SearchCompletion에서 MKLocalSearchCompletion으로의 검색이 가능한 매핑 경로가 있는가 | Apple 구현체 설계 확인 (Phase 2 선행 검증) |
| V1-5 | LBSServiceProvider 싱글톤이 정상 초기화되는가 | 빌드 후 앱 실행 확인 |
| V1-6 | 기존 코드와의 충돌 없이 새 파일이 추가되는가 | pbxproj auto-sync 확인 (PBXFileSystemSynchronizedRootGroup) |
