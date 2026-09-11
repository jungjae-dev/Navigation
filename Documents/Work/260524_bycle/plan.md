# 따릉이 기능 — 설계 및 개발 계획

> 작성일: 2026-05-24
> 참고: [requirements.md](./requirements.md), [api_research.md](./api_research.md)

---

## 1. 전체 아키텍처

### 1-1. 레이어 구조

```
┌──────────────────────────────────────────────────┐
│  Feature/Bike (UI 레이어)                        │
│  ──────────────────────────────────────────────  │
│  BikeLayerToggle  ─→  HomeViewController        │
│  BikeAnnotation                                  │
│  BikeAnnotationView                              │
│  BikeClusterAnnotationView                       │
│  BikeStationDetailViewController                 │
│    └ UIHostingController<BikeStationDetailView>  │
│  BikeStationDetailView (SwiftUI)                 │
│  BikeViewModel                                   │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│  Cache/BikeStationCache (싱글톤, in-memory)      │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│  Service/SeoulOpenAPI (네트워크 레이어)          │
│  ──────────────────────────────────────────────  │
│  SeoulAPIClient                                  │
│  BikeStationAPI                                  │
└──────────────────────┬───────────────────────────┘
                       │
                ┌──────▼──────┐
                │  openapi.   │
                │ seoul.go.kr │
                └─────────────┘
```

### 1-2. 책임 분리

| 모듈 | 책임 |
|---|---|
| `SeoulAPIClient` | URL 조립, 네트워크 호출, JSON 파싱, 에러 매핑 |
| `BikeStationAPI` | bikeList 전용 (전체 4분할, 단건 호출 메서드) |
| `BikeStationCache` | 메모리 캐시, stationId 인덱스, 갱신 시각 보관 |
| `BikeViewModel` | UI 상태 (loading/loaded/error), 갱신 트리거 |
| `BikeAnnotation` / View | 지도 마커 표현 |
| `BikeStationDetailSheet` | 상세 정보 표시, 액션 라우팅 |

---

## 2. 데이터 흐름

### 2-1. 토글 ON 흐름
```
사용자 토글 탭
  ↓
BikeViewModel.toggleOn()
  ↓
BikeStationCache가 비어있으면 → BikeStationAPI.fetchAll()
  └─ SeoulAPIClient × 4회 병렬 호출
  ↓
응답 합쳐서 [BikeStation] 으로 디코드
  ↓
BikeStationCache.update(stations)
  ↓
HomeViewController가 캐시 구독 → mapView.addAnnotations()
```

### 2-2. 정류소 탭 흐름 (기존 POI 드로어 패턴 재사용)
```
사용자 마커 탭
  ↓
mapView(_:didSelect:) → BikeAnnotation 식별
  ↓
mapVC.onBikeStationSelected(station)  콜백
  ↓
AppCoordinator.showBikeStationDetail(station)
  ↓
BikeStationDetailViewController 생성 (UIHostingController 래핑)
  ↓
DrawerContainerManager.pushDrawer(bikeDetailVC)   ← 기존 매니저 재사용
  ↓
사용자 닫기 → 드로어 pop, 마커 deselect
```

**기존 POI 흐름과의 일관성**
- `POIDetailViewController`와 동일하게 `DrawerContainerManager` 스택에 push
- detents 설정도 동일 패턴 (필요 시 따릉이 전용 detents)
- 닫기 시 이전 드로어로 자동 복귀

### 2-3. 새로고침 흐름
```
시트 [새로고침] 탭
  ↓
BikeStationAPI.fetchOne(stationId)
  ↓
BikeStationCache.update(single: station)
  ↓
시트 rootView 갱신
```

### 2-4. 도보 길찾기 흐름
```
시트 [도보 길찾기] 탭
  ↓
시트 dismiss → HomeViewController.requestWalkingRoute(to: station.coordinate)
  ↓
기존 AppCoordinator.showRoutePreview(...) 호출, transportMode=.walking
```

### 2-5. 대여하기 흐름
```
시트 [대여하기] 탭
  ↓
UIApplication.shared.canOpenURL(따릉이 scheme)
  ├─ true → 따릉이 앱 실행
  └─ false → App Store URL 열기
```

---

## 3. 컴포넌트 설계

### 3-1. SeoulAPIClient
```swift
final class SeoulAPIClient {
    static let shared = SeoulAPIClient(apiKey: AppConfig.seoulOpenAPIKey)

    func request<T: Decodable>(
        path: String,
        responseType: T.Type
    ) async throws -> T
}
```
- baseURL: `http://openapi.seoul.go.kr:8088`
- 공통 에러 매핑 (`INFO-100`, `ERROR-500` 등 → `SeoulAPIError` enum)

### 3-2. BikeStationAPI
```swift
struct BikeStationAPI {
    private let client: SeoulAPIClient

    /// 전체 정류소 4분할 병렬 호출
    func fetchAll() async throws -> [BikeStation]

    /// 단건 새로고침 (미문서화 패턴 활용)
    func fetchOne(stationId: String) async throws -> BikeStation?
}
```

### 3-3. BikeStation (Model)
```swift
struct BikeStation: Decodable, Hashable, Sendable {
    let stationId: String
    let stationName: String
    let coordinate: CLLocationCoordinate2D
    let totalRacks: Int           // rackTotCnt
    let availableBikes: Int       // parkingBikeTotCnt
    let shared: Int               // 거치율
    var availableRacks: Int { totalRacks - availableBikes }
}
```
- 응답 필드(String) → 적절한 타입으로 캐스팅

### 3-4. BikeStationCache
```swift
@MainActor
final class BikeStationCache {
    static let shared = BikeStationCache()

    private(set) var stations: CurrentValueSubject<[BikeStation], Never>
    private(set) var lastUpdated: CurrentValueSubject<Date?, Never>
    private var stationsById: [String: BikeStation] = [:]

    func station(id: String) -> BikeStation?
    func update(_ stations: [BikeStation])
    func update(single station: BikeStation)
    func clear()
}
```

### 3-5. BikeViewModel
```swift
@MainActor
final class BikeViewModel: ObservableObject {
    enum State { case idle, loading, loaded, error(Error) }

    @Published var state: State = .idle
    @Published var isLayerOn: Bool = false

    func toggleLayer() async
    func refreshSingle(stationId: String) async
}
```

### 3-6. BikeAnnotation / BikeAnnotationView
```swift
final class BikeAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let station: BikeStation
}

final class BikeAnnotationView: MKAnnotationView {
    // 원형 배경 + 잔여 자전거 수 라벨
    // 색상: 5대+ 녹색 / 1~4 주황 / 0 회색
    // clusteringIdentifier = "bike"
}

final class BikeClusterAnnotationView: MKAnnotationView {
    // 클러스터 — 그룹 내 정류소 수, 잔여 자전거 합계
}
```

### 3-7. BikeStationDetailViewController + SwiftUI View

기존 `POIDetailViewController`와 동일한 패턴 — UIKit `UIHostingController`로 SwiftUI 시트를 래핑하고 `DrawerContainerManager`에 push.

```swift
final class BikeStationDetailViewController: UIHostingController<BikeStationDetailView> {
    private let viewModel: BikeStationDetailViewModel

    var onRent: (() -> Void)?
    var onWalkingRoute: ((CLLocationCoordinate2D) -> Void)?
    var onClose: (() -> Void)?

    init(station: BikeStation) {
        self.viewModel = BikeStationDetailViewModel(station: station)
        super.init(rootView: BikeStationDetailView(viewModel: viewModel))
        // 콜백 → SwiftUI 뷰에 주입
    }
}

struct BikeStationDetailView: View {
    @ObservedObject var viewModel: BikeStationDetailViewModel
    let onRent: () -> Void
    let onWalkingRoute: () -> Void
    let onRefresh: () -> Void
    // close는 드로어 매니저가 처리
}
```

**드로어 등록 시점**:
```swift
// AppCoordinator
func showBikeStationDetail(_ station: BikeStation) {
    let detailVC = BikeStationDetailViewController(station: station)
    detailVC.onWalkingRoute = { [weak self] coord in
        self?.showRoutePreview(to: coord, transportMode: .walking)
    }
    detailVC.onRent = { BikeAppLauncher.openOrInstall() }

    drawerManager.pushDrawer(
        detailVC,
        detents: bikeDetailDetents(),
        initialDetent: bikeDetailInitialDetent()
    )
}
```

---

## 4. 단계별 개발 계획 + 검증 항목

각 단계는 **독립적으로 빌드 가능한 단위**로 분리. 단계 완료 시 체크리스트로 검증.

---

### Phase 1 — API 키 + 네트워크 클라이언트

**작업**
- 서울 열린데이터광장에서 일반 인증키 발급
- 키를 Build Settings의 `INFOPLIST_KEY_SEOUL_OPEN_API_KEY` 로 주입
- `AppConfig.seoulOpenAPIKey` 읽기 헬퍼 추가
- `SeoulAPIClient` 구현 (request + 에러 매핑)
- `BikeStationAPI.fetchAll()` 구현 (4분할 병렬)
- `BikeStation` 모델 정의

**파일**
- `Service/SeoulOpenAPI/SeoulAPIClient.swift`
- `Service/SeoulOpenAPI/SeoulAPIError.swift`
- `Service/SeoulOpenAPI/BikeStationAPI.swift`
- `Model/BikeStation.swift`
- `Common/AppConfig.swift` (수정)

**검증 항목**
- [ ] 빈 API 키일 때 `SeoulAPIError.missingAPIKey` 발생
- [ ] `fetchAll()` 호출 시 4번의 네트워크 요청이 병렬로 발생
- [ ] 응답 총합이 `list_total_count` 와 일치
- [ ] `INFO-100` (잘못된 키) → `SeoulAPIError.invalidAPIKey`로 매핑
- [ ] `INFO-200` (데이터 없음) → 빈 배열 반환, 에러 아님
- [ ] 네트워크 에러 시 `SeoulAPIError.network` 반환
- [ ] 단위 테스트: stub 응답으로 모델 파싱 검증

---

### Phase 2 — 캐시 + ViewModel

**작업**
- `BikeStationCache` 싱글톤 구현 (`@MainActor`)
- stationId 인덱스 (`[String: BikeStation]`) 동기화
- `BikeViewModel` 구현 (state, fetch trigger)
- 단건 갱신 API (`fetchOne`) 추가

**파일**
- `Cache/BikeStationCache.swift`
- `Feature/Bike/BikeViewModel.swift`
- `Service/SeoulOpenAPI/BikeStationAPI.swift` (수정 — fetchOne 추가)

**검증 항목**
- [ ] `update(_:)` 호출 후 `stations` Publisher가 새 값 발행
- [ ] `update(single:)` 호출 시 해당 stationId만 교체, 다른 항목 유지
- [ ] `station(id:)` 가 O(1) lookup
- [ ] `clear()` 호출 시 빈 배열 + nil 시각
- [ ] `BikeViewModel.toggleLayer()` 호출 시 state 전이: idle → loading → loaded
- [ ] 에러 시 state: loading → error
- [ ] `fetchOne` 으로 받은 단건이 캐시에 반영됨

---

### Phase 3 — 토글 버튼 UI

**작업**
- `MapControlButtonsView` 에 따릉이 토글 버튼 추가
- 버튼 OFF/ON 시각 상태 (회색 아웃라인 / 파란 채움)
- `HomeViewController` 에서 토글 콜백 연결 (현재는 print만)

**파일**
- `Feature/Home/MapControlButtonsView.swift` (수정)
- `Feature/Home/HomeViewController.swift` (수정)
- `Feature/Bike/BikeLayerToggle.swift` (선택 — 별도 분리 시)

**검증 항목**
- [ ] 토글 버튼이 기존 현위치/지도모드 스택 아래에 노출됨
- [ ] OFF 상태: 회색 아웃라인 아이콘
- [ ] ON 상태: 파란 채움 아이콘
- [ ] 탭할 때마다 ON/OFF 전환됨
- [ ] 다크모드에서 색상 명확히 구분됨
- [ ] 접근성 라벨: "따릉이 정류소 표시"

---

### Phase 4 — 지도 마커 표시 (잔여 수 배지)

**작업**
- `BikeAnnotation` 정의
- `BikeAnnotationView` 구현 (원형 배경 + 숫자, 색상 코드)
- `HomeViewController.mapView(_:viewFor:)` 에 분기 추가
- 토글 ON → 캐시 fetch → 지도에 annotation 추가
- 토글 OFF → annotation 모두 제거

**파일**
- `Feature/Bike/BikeAnnotation.swift`
- `Feature/Bike/BikeAnnotationView.swift`
- `Feature/Home/HomeViewController.swift` (수정)

**검증 항목**
- [ ] 토글 ON 시 1초 이내 마커가 지도에 표시됨 (정상 네트워크)
- [ ] 잔여 자전거 5대 이상 → 녹색 마커
- [ ] 잔여 자전거 1~4대 → 주황 마커
- [ ] 잔여 자전거 0대 → 회색 마커
- [ ] 마커에 잔여 자전거 수가 숫자로 표시됨
- [ ] 토글 OFF 시 모든 마커 제거됨
- [ ] 지도 줌/팬 시 성능 60fps 유지 (~3,000개)
- [ ] 다크모드에서 배지 가독성 유지

---

### Phase 5 — 클러스터링 적용

**작업**
- `BikeAnnotationView.clusteringIdentifier = "bike"`
- `BikeClusterAnnotationView` 구현 (그룹 내 정류소 수 + 잔여 합계)
- `mapView(_:viewFor:)` 에서 `MKClusterAnnotation` 분기 추가

**파일**
- `Feature/Bike/BikeAnnotationView.swift` (수정)
- `Feature/Bike/BikeClusterAnnotationView.swift`
- `Feature/Home/HomeViewController.swift` (수정)

**검증 항목**
- [ ] 서울 전체 줌 아웃 시 자동 클러스터 형성
- [ ] 줌 인 시 클러스터가 자동으로 개별 마커로 분해
- [ ] 클러스터에 그룹 내 정류소 수 표시
- [ ] 클러스터 탭 시 자동 확대 동작
- [ ] 60fps 유지

---

### Phase 6 — 상세 시트 (따릉이 전용, 기존 드로어 패턴)

**작업**
- `BikeStationDetailView` SwiftUI 뷰 구현 (시트 컨텐츠)
- `BikeStationDetailViewModel` (단일 station 보유, 새로고침 트리거)
- `BikeStationDetailViewController` 생성 (UIHostingController 래핑, 기존 POIDetailViewController 와 동일 패턴)
- 마커 탭 → `MapViewController.onBikeStationSelected` 콜백
- `AppCoordinator.showBikeStationDetail()` → `DrawerContainerManager.pushDrawer()`
- 정류소 전환 시 기존 BikeStationDetailVC를 새 정류소로 update (또는 replaceStack)

**파일**
- `Feature/Bike/BikeStationDetailView.swift` (SwiftUI)
- `Feature/Bike/BikeStationDetailViewController.swift` (UIHostingController)
- `Feature/Bike/BikeStationDetailViewModel.swift`
- `Feature/Home/HomeViewController.swift` (수정 — 마커 탭 → 콜백 라우팅)
- `Map/MapViewController.swift` (수정 — `onBikeStationSelected` 콜백 추가)
- `Coordinator/AppCoordinator.swift` (수정 — `showBikeStationDetail` 메서드)

**검증 항목**
- [ ] 마커 탭 시 드로어가 정류소 상세로 push (기존 POI 흐름과 동일하게 동작)
- [ ] 정류소 이름, 대여 가능, 반납 가능, 거리, 갱신 시각 정확히 표시
- [ ] 잔여 자전거 수 색상이 마커와 일관됨
- [ ] 드로어 닫기 (드래그 아래, 또는 X 버튼) → 마커 deselect + 이전 드로어로 pop
- [ ] 두 정류소 연속 탭 시 동일 드로어에서 컨텐츠만 update (스택이 누적되지 않음)
- [ ] 홈 드로어와 정류소 상세 드로어 간 detent 일관성 (필요 시 따릉이 전용 detent)

---

### Phase 7 — 도보 길찾기 연결

**작업**
- 상세 시트의 `도보 길찾기` 버튼 → 기존 RoutePreview / Navigation 호출
- 전달 정보: 현재 위치 → 정류소 좌표, 모드 `.walking`

**파일**
- `Feature/Bike/BikeStationDetailSheet.swift` (콜백 호출)
- `Feature/Home/HomeViewController.swift` (수정)
- `Coordinator/AppCoordinator.swift` (필요 시 수정)

**검증 항목**
- [ ] 버튼 탭 시 기존 RoutePreview 화면이 열림
- [ ] 출발지 = 현재 위치, 목적지 = 정류소
- [ ] transportMode 가 `.walking` 으로 전달됨
- [ ] 길찾기 시작 → 도보 모드 안내 진행
- [ ] 도착 시 정류소 좌표 ± 오차 범위 내

---

### Phase 8 — 대여 딥링크

**작업**
- `BikeAppLauncher.swift` 헬퍼 추가
  - 따릉이 앱 URL Scheme 시도 → 실패 시 App Store 이동
- `Info.plist` `LSApplicationQueriesSchemes` 에 따릉이 scheme 추가 (확인 후)
- 상세 시트의 `대여하기` 버튼 → 헬퍼 호출

**파일**
- `Feature/Bike/BikeAppLauncher.swift`
- `Info.plist` (수정)

**검증 항목**
- [ ] 따릉이 앱 설치 환경에서 버튼 탭 → 따릉이 앱 실행
- [ ] 따릉이 앱 미설치 환경에서 → App Store 따릉이 페이지로 이동
- [ ] App Store URL 정상 동작 (ID 1037272004)
- [ ] 시뮬레이터에서도 미설치 fallback 동작

---

### Phase 9 — 수동 새로고침

**작업**
- 상세 시트 새로고침 버튼 → `BikeStationAPI.fetchOne` 호출
- 캐시 단건 업데이트 → 시트 뷰 갱신
- 로딩 중 인디케이터 표시

**파일**
- `Feature/Bike/BikeStationDetailSheet.swift` (수정)
- `Feature/Bike/BikeStationDetailViewModel.swift` (수정)

**검증 항목**
- [ ] 새로고침 버튼 탭 시 로딩 인디케이터 표시
- [ ] 호출 완료 시 잔여 자전거 수 즉시 반영
- [ ] 갱신 시각 표시가 "방금 전" 또는 "0분 전" 으로 변경
- [ ] 네트워크 에러 시 사용자에게 토스트 등 알림
- [ ] 다른 정류소 마커는 영향 없음 (전체 fetch 안 함)

---

### Phase 10 — 통합 / 마무리

**작업**
- 빈 상태 처리 (서울 외 지역, 0개 정류소)
- 네트워크 에러 시 사용자 안내
- 다크모드 전체 점검
- 접근성 라벨 추가
- 빌드 설정에 API 키 누락 시 빌드 실패 처리 (또는 명확한 경고)
- 코드 정리, lint, 주석

**검증 항목**
- [ ] API 키 미설정 빌드 시 명확한 에러
- [ ] 네트워크 끊김 시 적절한 에러 UI
- [ ] 라이트/다크 모드 모두 색상/대비 OK
- [ ] VoiceOver: 토글 버튼, 마커, 시트 모든 요소가 읽힘
- [ ] 시뮬레이터: iPhone 17 Pro / iPad Pro 모두 정상
- [ ] 실기기 1회 이상 검증
- [ ] 메모리 누수 없음 (Instruments)

---

## 5. 통합 테스트 시나리오

### TC-1: 토글 사이클
1. 따릉이 토글 ON
2. 지도에 마커 표시 확인
3. 토글 OFF
4. 마커 제거 확인
5. 토글 ON
6. 캐시에서 즉시 표시 (재호출 없음 검증)

### TC-2: 정류소 상세 사이클
1. 토글 ON
2. 정류소 마커 탭
3. 시트 표시 확인 (정보 정확성)
4. 새로고침 버튼 탭 → 잔여 수 갱신
5. 닫기 → 시트 dismiss + 마커 선택 해제

### TC-3: 도보 길찾기
1. 정류소 선택
2. 도보 길찾기 탭
3. RoutePreview → Navigation 진입
4. 도보 모드 turn-by-turn 진행

### TC-4: 대여 딥링크
1. 정류소 선택
2. 대여하기 탭
3. 따릉이 앱 실행 또는 App Store 이동 확인

### TC-5: 에러 처리
1. 네트워크 끊고 토글 ON → 에러 메시지 표시
2. 잘못된 API 키 → 명확한 에러
3. 단건 새로고침 실패 → 기존 캐시 유지

---

## 6. 위험 / 미해결 항목

| 항목 | 영향 | 대응 |
|---|---|---|
| 따릉이 URL Scheme 미확인 | 대여 버튼 시 즉시 App Store로 가야 할 수도 | IPA 분석 후 결정, 임시로는 App Store 폴백 |
| 미문서화 단건 조회 의존 | 서울시가 차단할 가능성 | 차단 시 전체 fetch로 대체 (코드 분기) |
| 일일 1,000회 API 한도 | 트래픽 폭주 시 차단 | 명시적 갱신만 사용, 활용사례 등록으로 한도 확장 |
| ~3,000개 마커 렌더 성능 | 저사양 기기에서 끊김 | 클러스터링 + 가시 영역 필터링 |

---

## 7. 산출물 체크리스트 (전 단계 완료 시)

- [ ] Phase 1~10 모두 완료 + 각 검증 항목 통과
- [ ] 단위 테스트: API 파싱, 캐시 동작, 색상 매핑
- [ ] 통합 테스트: TC-1~TC-5 모두 통과
- [ ] 다크모드 검증
- [ ] 접근성 검증
- [ ] requirements.md 완료 기준 모두 만족
- [ ] 새 폴더 구조 정리, 폴더별 README 또는 코드 주석
- [ ] PR 작성 (브랜치 + 커밋 메시지 정리)
