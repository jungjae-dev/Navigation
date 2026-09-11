# 따릉이 정류소 기능 통합 — 개발 완료 보고서

| 항목 | 내용 |
|---|---|
| 브랜치 | `feature/39-add-bycle` |
| 기간 | 2026-05-24 ~ 2026-05-25 |
| 변경 규모 | +1,545 / −306 줄 · 24 파일 |
| 커밋 | 15건 (Phase 1 → Phase 9 + 리팩토링) |

---

## 1. 요약

서울시 공공자전거 따릉이 데이터를 지도에 통합한다. 단순한 정류소 표시를 넘어:

- 기존 POI 상세 시트와 신규 따릉이 상세 시트를 하나의 추상화(`MapItemContent`) 위에서 호스팅하도록 **상세 시트 구조를 재설계**
- 지도 빈 곳 탭 / POI ↔ POI 전환 / annotation 충돌 등 **지도 인터랙션 모델을 정리**
- 코드 리뷰를 반영해 **Critical / Suggestion 항목 종결**

---

## 2. 시스템 구성

### 2-1. 전체 흐름

```
┌──────────────────┐    토글 ON    ┌──────────────────┐
│ HomeViewController├──────────────►│ BikeViewModel    │
└──────────────────┘                │  (@MainActor)    │
        ▲                           └────────┬─────────┘
        │ 상태 구독                          │ fetchAll()
        │                                    ▼
        │                           ┌──────────────────┐
        │                           │ BikeStationAPI   │
        │                           │  - 4-way 병렬     │
        │                           │  - non-throwing   │
        │                           │    TaskGroup      │
        │                           └────────┬─────────┘
        │                                    │ try await
        │                                    ▼
        │                           ┌──────────────────┐
        │                           │ SeoulAPIClient   │
        │                           │  URL + auth key  │
        │                           └────────┬─────────┘
        │                                    │ HTTP
        │                                    ▼
        │                           ┌──────────────────┐
        │     update                │ openapi.seoul.go │
        │     (single/all)          │ .kr:8088         │
        │                           └──────────────────┘
        ▼                                    ▲
┌──────────────────┐                         │
│ BikeStationCache │◄────────────────────────┘
│ (@MainActor)     │   결과 반영
│ CurrentValueSubject<[BikeStation]>
└────────┬─────────┘
         │ Combine
         ▼
┌──────────────────┐                ┌──────────────────────────┐
│ MapViewController├───────────────►│ BikeAnnotationView ×N   │
│   zoom threshold │   addAnnotations │ MKMarkerAnnotationView   │
│   latΔ ≤ 0.05    │                │ + glyphText = 잔여수      │
└──────────────────┘                └──────────────────────────┘
```

### 2-2. 신규 모듈 — Seoul Open API 레이어

```
Navigation/Service/SeoulOpenAPI/
├── SeoulAPIClient.swift          공통 HTTP 클라이언트
├── SeoulAPIConfig.swift          baseURL + 인증키 (Info.plist 주입)
├── SeoulAPIError.swift           INFO-XXX / ERROR-XXX → enum
└── Bike/
    ├── BikeStationAPI.swift          fetchAll / fetchOne
    ├── BikeStation.swift             서비스 모델
    ├── BikeStationResponse.swift     DTO + decodeStations()
    └── BikeStationCache.swift        @MainActor 메모리 캐시 (싱글톤)
```

`fetchAll` 페이지 처리:

```
            ┌─ fetchPage(   1, 1000) ─┐
TaskGroup ──┼─ fetchPage(1001, 2000) ─┤── dedup(stationId) → [BikeStation]
            ├─ fetchPage(2001, 3000) ─┤
            └─ fetchPage(3001, 4000) ─┘
              ↑ 각 task 내부 do/catch  — 한 페이지 실패가 다른 페이지를 취소시키지 않음
```

### 2-3. MapItemContent — 상세 시트 추상화

기존 `POIDetailViewController` (258줄, scaffold + POI 전용 혼재) 삭제. 다음 구조로 재설계:

```
┌──────────────────────────────────────────────────┐
│ MapItemDetailViewController                      │
│   ┌──────────────────────────────────────────┐   │
│   │ DrawerHeaderView (icon + title + close)  │   │
│   ├──────────────────────────────────────────┤   │
│   │ contentContainer  ← content.contentView  │   │  ← 컨텐츠 swap 지점
│   ├──────────────────────────────────────────┤   │
│   │ footer (DrawerFooterProviding)           │   │
│   │   rebuildFooterButtons() ← footerActions │   │
│   └──────────────────────────────────────────┘   │
│   update(content:) → 헤더/본문/푸터 일괄 갱신    │
└──────────────────────┬───────────────────────────┘
                       │ hosts (any MapItemContent)
       ┌───────────────┼─────────────────┐
       ▼               ▼                 ▼
  PlaceContent    BikeStationContent   (future: Bus/Subway)
  + Place         + BikeStation
    Content         Content
    View            View
```

`MapItemContent` 프로토콜:

```swift
protocol MapItemContent: AnyObject {
    var iconImage: UIImage? { get }
    var title: String { get }
    var identifier: String { get }
    var contentView: UIView { get }
    var footerActions: [MapItemAction] { get }
    func updateDistance(from coordinate: CLLocationCoordinate2D?)
}
```

`AppCoordinator.showMapItemDetail(content:)` 단일 진입점:
- 드로어 없음 → 새로 push
- 드로어 있음 → `update(content:)` (헤더/본문/푸터 동시 swap, 재push 없음)

---

## 3. Phase 별 변경

| Phase | 내용 | 핵심 파일 |
|---|---|---|
| 1 | API 키 + 공통 클라이언트 | `SeoulAPIClient`, `SeoulAPIConfig`, `SeoulAPIError` |
| 2 | 캐시 + ViewModel | `BikeStationCache`, `BikeViewModel` |
| 3 | 레이어 토글 버튼 | `MapControlButtonsView`, `HomeViewController` |
| 4 | 지도 마커 (zoom threshold) | `BikeAnnotation`, `BikeAnnotationView`, `MapViewController` |
| 5 | (스킵) 클러스터링 → zoom threshold 대체 | — |
| 6 | POI/따릉이 상세 시트 통합 | `MapItemDetailViewController`, `MapItemContent`, `Place/BikeStationContent[View]` |
| 7 | 정류소까지 도보 길찾기 | `AppCoordinator.showWalkingRouteToBikeStation` |
| 8 | 따릉이 앱 대여 딥링크 | `BikeAppLauncher`, `Info.plist` |
| 9 | 수동 새로고침 | `MapControlButtonsView.bikeRefreshButton` |

---

## 4. 지도 인터랙션 모델 정리

### 4-1. 빈 곳 탭 → 드로어 닫기

문제: MapKit이 빈 곳 탭 전용 이벤트를 제공하지 않음. UITapGestureRecognizer + hitTest 는 `MKMapFeatureAnnotation` (view 없음) 과 빈 곳을 구분 불가.

해결: `didDeselect` 기반 + 50ms 디바운스. POI feature 의 동기 deselect 부작용은 "우리가 관리하는 custom annotation 만 close 후보"로 차단.

```
사용자 tap (빈 곳)
    │
    ▼  ~500ms (MapKit 내부 단일/이중 탭 disambiguation)
didDeselect(POIAnnotation / BikeAnnotation / SearchResultAnnotation)
    │
    ▼  +50ms debounce
selectedAnnotations.isEmpty ?
    ├─ true  → onEmptyMapTapped → dismissMapItemDetailWithCleanup
    └─ false → 다른 annotation 이 선택됨, no-op
```

대체 흐름:

```
POI A 선택 상태에서 POI B 탭
    didDeselect(POIAnnotation A)        → close 예약
    didSelect(MKMapFeatureAnnotation B) → 예약 취소  ✓
    deselect(B) [동기]
        didDeselect(B) → 우리 관리 아님, 무시
        didDeselect("Other") → 우리 관리 아님, 무시
    async fetch mapItem
    didSelect(POIAnnotation B)          → 드로어 update()
```

### 4-2. annotation 충돌 처리

`MKMarkerAnnotationView` 기본 `collisionMode = .rectangle` 이라 따릉이 마커 위에 POI / 검색결과 마커가 가려지는 문제가 발생.

```
모든 우리 마커:  displayPriority = .required
                collisionMode  = .none      ← 겹쳐도 항상 표시
```

`BikeAnnotation`, `POIAnnotation`, `SearchResultAnnotation` 뷰 모두 동일 정책.

### 4-3. 줌 threshold

전체 2,734개 정류소를 한 번에 표시하면 클러스터링 캐시가 비정상 동작. 클러스터링 대신 단순한 임계값 기반 가시성 토글로 처리.

```
regionDidChange
    │
    ▼
latΔ ≤ 0.05 (bikeMaxLatitudeDelta) ?
    ├─ true  → mapView.addAnnotations(bikeAnnotations)
    └─ false → mapView.removeAnnotations(displayed)
```

---

## 5. 외부 연동

### 5-1. RoutePreview 연동 (도보 길찾기)

```
BikeStationContent.onWalkingRoute(station)
    │
    ▼
AppCoordinator.showWalkingRouteToBikeStation(station)
    ├─ dismissMapItemDetailWithCleanup()
    ├─ mapViewController.showDestination(...)
    └─ presentRoutePreviewDrawer(
          origin: locationService.bestAvailableLocation,
          destination: station.coordinate,
          destinationName: station.stationName,
          transportMode: .walking          ← 신규 파라미터
       )
```

### 5-2. 따릉이 앱 대여 딥링크

```
BikeStationContent.onRent
    │
    ▼
BikeAppLauncher.openRent()
    ├─ canOpenURL("bikeseoul://") ?
    │     ├─ true  → UIApplication.shared.open(...)
    │     └─ false ─┐
    │               ▼
    │            itms-apps://apps.apple.com/app/id1037272004
    │               │ canOpen ?
    │               ├─ true  → open
    │               └─ false → https 폴백
```

- `Info.plist > LSApplicationQueriesSchemes` 에 `bikeseoul` 등록
- 정류소 ID 전달 path 는 공개 문서 없음 → 앱 메인 진입만 지원 (한계)

---

## 6. 리팩토링 / 코드 리뷰 반영

### Critical
| 항목 | 변경 |
|---|---|
| `BikeStationAPI.fetchAll` | `throwing TaskGroup` → `non-throwing` + 페이지별 do/catch (한 페이지 실패가 다른 페이지를 취소시키지 않도록) |
| `SeoulAPIError.from(code:)` | `"INFO-000"` 성공 코드에 대한 `fatalError` 제거, `.unknown` 안전화 |

### Suggestion
| 항목 | 변경 |
|---|---|
| brandGreen 중복 | `Theme.Colors.bikeBrand` 추가, 2곳 통합 |
| `BikeViewModel` race | `isFetching` 가드로 `toggleLayer` / `fetchAll` 재진입 차단 |
| 매직 넘버 | `bikeMaxLatitudeDelta`, `emptyTapCloseDebounce` 상수화 |
| 메모리 / lifecycle | `MapViewController.deinit` 에서 `pendingEmptyTapCheck` cancel |
| DI | `BikeStationContent` 가 `cache: BikeStationCache` 주입 받음 (기본 `.shared`) |
| Combine 효율 | `subscribeCache` 가 `compactMap` + `removeDuplicates(by:)` 로 자기 정류소 변경만 sink |

---

## 7. 발견 / 처리한 부수 이슈

| 이슈 | 원인 | 해결 |
|---|---|---|
| POI 마커가 따릉이 마커에 가려짐 | `collisionMode = .rectangle` 기본값 | `collisionMode = .none` 명시 |
| 검색 결과 마커가 따릉이 마커에 가려짐 | 동일 | 동일 |
| 새로고침 버튼 탭이 지도로 통과 | 부모 view bounds 밖에 위치 | `point(inside:with:)` 오버라이드로 hit 영역 확장 |
| MKMarkerAnnotationView 빨간 그림자 | 시스템 내부 — public API로 제거 불가 | 노란 glyph + 잔여수 표시로 시각 노이즈 줄임 (수용) |
| 빈 곳 탭 2번 필요 | 디바운스 0.7s 동안 selectedAnnotations 자동 정리 안 됨 | trigger 를 tap → didDeselect 로 전환, 0.05s 디바운스 |
| POI ↔ POI 전환 시 드로어 재push | swap 도중 비동기 fetch gap | 우리 custom annotation 만 close 후보로 처리 |
| 거치대 초과 시 "반납 가능 0" 오해 | 거치대 외 자전거 누적은 정상 | "반납 가능" 컬럼 자체 제거 |

---

## 8. 한계 / 미해결

| 항목 | 설명 |
|---|---|
| 일반/새싹 자전거 구분 불가 | 서울 공개 API 는 합산(`parkingBikeTotCnt`) 만 제공 |
| 따릉이 앱 정류소 직접 진입 불가 | `bikeseoul://` path 비공개 — 앱 메인만 진입 |
| 개인 대여 정보 (잔여 시간 등) | 인증 기반 비공개 API — 외부 앱에서 접근 불가 |
| API 인증키는 일반키 (지하철과 별도) | 호출량 제한 모니터링 필요 |

---

## 9. 변경 파일 (24)

```
신규 (16)
  Service/SeoulOpenAPI/SeoulAPIClient.swift
  Service/SeoulOpenAPI/SeoulAPIConfig.swift
  Service/SeoulOpenAPI/SeoulAPIError.swift
  Service/SeoulOpenAPI/Bike/BikeStation.swift
  Service/SeoulOpenAPI/Bike/BikeStationAPI.swift
  Service/SeoulOpenAPI/Bike/BikeStationCache.swift
  Service/SeoulOpenAPI/Bike/BikeStationResponse.swift
  Feature/Bike/BikeAnnotation.swift
  Feature/Bike/BikeAnnotationView.swift
  Feature/Bike/BikeAppLauncher.swift
  Feature/Bike/BikeViewModel.swift
  Feature/MapItemDetail/MapItemContent.swift
  Feature/MapItemDetail/MapItemDetailViewController.swift
  Feature/MapItemDetail/Content/PlaceContent.swift
  Feature/MapItemDetail/Content/PlaceContentView.swift
  Feature/MapItemDetail/Content/BikeStationContent.swift
  Feature/MapItemDetail/Content/BikeStationContentView.swift

수정 (7)
  Common/UI/Theme.swift              (bikeBrand)
  Coordinator/AppCoordinator.swift   (MapItemDetail flow, walking route 등)
  Feature/Home/HomeViewController.swift     (BikeViewModel 통합)
  Feature/Home/MapControlButtonsView.swift  (토글/새로고침 + hitTest)
  Map/MapViewController.swift        (bike annotations + empty-tap + collision)
  Info.plist                         (Seoul API 키 + bikeseoul scheme)

삭제 (1)
  Feature/POIDetail/POIDetailViewController.swift  (258줄)
```

---

## 10. 테스트 시나리오

- [x] 토글 ON → 마커 표시 / OFF → 숨김 / 재 ON → 캐시 hit
- [x] 줌 아웃 (latΔ > 0.05) 시 마커 자동 숨김 / 복원
- [x] 새로고침 버튼 → 잔여 수 갱신 + 상세 시트 자동 반영
- [x] 정류소 탭 → 1.5배 확대 + 상세 시트 표시
- [x] POI ↔ POI / POI ↔ 따릉이 전환 시 시트 내용만 갱신
- [x] 지도 빈 곳 탭 → 시트 닫힘
- [x] 도보 길찾기 → RoutePreview (.walking) 진입
- [x] 대여하기 → 따릉이 앱 (미설치 시 App Store)
- [x] POI / 검색 결과 마커가 따릉이 마커와 겹쳐도 항상 표시
