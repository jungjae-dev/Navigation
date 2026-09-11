# LBS Provider 분리 — 구현 플랜

## Phase 1: LBSServiceProvider 분리

**목표**: 단일 providerType → searchProviderType + routeProviderType 독립화

### 변경: `LBSServiceProvider.swift`

```swift
// 기존
private(set) var providerType: LBSProviderType

// 변경
private(set) var searchProviderType: LBSProviderType
private(set) var routeProviderType: LBSProviderType
```

**UserDefaults 마이그레이션 (init에서 1회 실행)**

```swift
// route_provider만 레거시 값 인계, search_provider는 항상 Kakao 고정
if let legacy = UserDefaults.standard.string(forKey: "lbs_provider") {
    UserDefaults.standard.set(legacy, forKey: "route_provider")   // 기존 설정 유지
    // search_provider는 레거시 무시 → 기본값 kakao 사용
    UserDefaults.standard.removeObject(forKey: "lbs_provider")
}
```

> 이유: 검색 기본값은 항상 Kakao여야 함. 기존에 Apple을 선택했더라도 검색은 Kakao로 고정.

**makeServices 분리**

```swift
// 검색 + geocoding
private static func makeSearchServices(for type: LBSProviderType)
    -> (SearchProviding, GeocodingProviding)

// 경로
private static func makeRouteService(for type: LBSProviderType)
    -> RouteProviding
```

**공개 API**

```swift
func switchSearchProvider(to type: LBSProviderType)
func switchRouteProvider(to type: LBSProviderType)
```

**검증**: `LBSServiceProvider.shared.searchProviderType` / `routeProviderType` 출력으로 분리 확인

---

## Phase 2: 카카오 검색 429 처리 — 팝업 후 종료

**목표**: 카카오 검색 한도 초과 시 Apple 폴백 없이 팝업만 표시하고 검색 중단

### 설계 변경

기존 FallbackSearchService의 quotaExceeded → Apple 폴백 로직을 **제거**.
한도 초과 시 사용자에게 알리고 깔끔하게 실패 처리.

> 이유: Apple 검색은 한국 POI 품질이 낮아 폴백해봤자 사용자 불만. 차라리 명확하게 알리는 게 낫다.

### `FallbackSearchService.swift` 변경

**search / searchCategory / search(for:) 3개 메서드 공통 변경**

```swift
// 기존: quotaExceeded → Apple 폴백
} catch let error as LBSError where error == .quotaExceeded {
    return try await fallback.search(query: query, region: region)
}

// 변경: quotaExceeded → Notification 발송 후 throw (폴백 없음, 상태 저장 없음)
} catch let error as LBSError where error == .quotaExceeded {
    NotificationCenter.default.post(name: .lbsSearchQuotaExceeded, object: nil)
    throw error
}
```

매 호출마다 429가 오면 팝업이 뜸. 상태 플래그 없음. 카카오 서버 한도가 풀리면 자연히 정상 복구.

### Notification 이름

```swift
// Notification.Name extension에 추가
static let lbsSearchQuotaExceeded = Notification.Name("lbsSearchQuotaExceeded")
```

### `FallbackRouteService.swift` Notification 이름 변경

```swift
// 기존
static let lbsProviderFallbackActivated = Notification.Name("lbsProviderFallbackActivated")
// 변경
static let lbsRouteFallbackActivated = Notification.Name("lbsRouteFallbackActivated")
```

**검증**: 429 강제 throw 후 Notification 발송 확인, Apple 폴백이 일어나지 않는지 확인

---

## Phase 3: 개발자 메뉴 업데이트

### `SettingsViewModel.swift`

```swift
// 기존
let lbsProvider = CurrentValueSubject<LBSProviderType, Never>(...)
func setLBSProvider(_ type: LBSProviderType)

// 변경
let searchProvider = CurrentValueSubject<LBSProviderType, Never>(
    LBSServiceProvider.shared.searchProviderType
)
let routeProvider = CurrentValueSubject<LBSProviderType, Never>(
    LBSServiceProvider.shared.routeProviderType
)
func setSearchProvider(_ type: LBSProviderType)
func setRouteProvider(_ type: LBSProviderType)
```

### `SettingsViewController.swift`

**Section 변경 불필요** — 기존 lbsProvider 섹션에 row 추가

```swift
// 기존 LBSProviderRow
enum LBSProviderRow { case provider }

// 변경
enum LBSProviderRow {
    case searchProvider   // "검색 제공자"
    case routeProvider    // "경로 제공자"
}
```

**cellForRowAt 변경**

```swift
case .searchProvider:
    cell.textLabel?.text = "검색 제공자"
    cell.detailTextLabel?.text = viewModel.searchProvider.value.displayName

case .routeProvider:
    cell.textLabel?.text = "경로 제공자"
    cell.detailTextLabel?.text = viewModel.routeProvider.value.displayName
```

**showSearchProviderPicker() / showRouteProviderPicker() 추가**

기존 `showLBSProviderPicker()` 패턴 그대로, target만 변경.

**viewModel 바인딩 추가**

```swift
viewModel.searchProvider
    .sink { [weak self] _ in self?.tableView.reloadSections(...) }
    .store(in: &cancellables)

viewModel.routeProvider
    .sink { [weak self] _ in self?.tableView.reloadSections(...) }
    .store(in: &cancellables)
```

**검증**: 개발자 메뉴 → "검색 제공자" / "경로 제공자" 각각 Kakao/Apple 선택 후 동작 확인

---

## Phase 4: 429 팝업 구현

**목표**: Notification 수신 → UIAlertController 표시

### 팝업 표시 위치

`HomeViewController` (최상위 뷰)에서 Notification 수신.

### 구현 패턴

```swift
// HomeViewController viewDidLoad에 추가
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleSearchQuotaExceeded),
    name: .lbsSearchQuotaExceeded,
    object: nil
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleRouteFallback),
    name: .lbsRouteFallbackActivated,
    object: nil
)
```

```swift
@objc private func handleSearchQuotaExceeded() {
    showAlert(
        title: "검색 한도 초과",
        message: "오늘 카카오 검색 한도에 도달했습니다.\n내일 자정에 자동으로 초기화됩니다."
    )
}

@objc private func handleRouteFallback() {
    guard LBSServiceProvider.shared.routeProviderType == .kakao else { return }
    showAlert(
        title: "경로 서비스 일시 제한",
        message: "카카오 경로 서비스가 일시적으로 제한됩니다.\n잠시 후 자동으로 복구됩니다."
    )
}

private func showAlert(title: String, message: String) {
    guard presentedViewController == nil else { return }
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "확인", style: .default))
    present(alert, animated: true)
}
```

**검증**: 429 강제 발생 → 팝업 표시 확인. 재시도 시 팝업 재표시 확인. 카카오 한도 복구 시 정상 동작 확인.

---

## 구현 순서 요약

| Phase | 작업 | 예상 소요 |
|-------|------|----------|
| 1 | LBSServiceProvider 분리 + 마이그레이션 + `.lbsSearchProviderChanged` Notification | 30분 |
| 2 | FallbackSearchService 업데이트 + Notification 이름 정리 | 20분 |
| 3 | SettingsViewModel + SettingsViewController 업데이트 | 40분 |
| 4 | 429 팝업 구현 (HomeViewController) | 20분 |
| 5 | HomeDrawerViewController 카테고리 갱신 | 15분 |
| - | 통합 테스트 | 30분 |

---

## Phase 5: HomeDrawerViewController 카테고리 갱신

**목표**: 개발자 메뉴에서 searchProvider 변경 시 홈 화면 카테고리 즉시 갱신

현재 `HomeDrawerViewController`는 `LBSServiceProvider.shared.search.supportedCategories`를
동적으로 참조하지만, provider 변경 후 `reloadData()` 트리거가 없음.

`SettingsViewModel.searchProvider`가 변경될 때 → `collectionView.reloadData()` 호출 필요.

구현 위치: `HomeDrawerViewController.bindViewModel()` 또는 Coordinator에서 처리.

```swift
// HomeDrawerViewController.bindViewModel() 에 추가
NotificationCenter.default.addObserver(
    self,
    selector: #selector(reloadCategories),
    name: .lbsSearchProviderChanged,
    object: nil
)

@objc private func reloadCategories() {
    collectionView.reloadSections(IndexSet(integer: HomeSection.categories.rawValue))
}
```

`LBSServiceProvider.switchSearchProvider(to:)` 내부에서 Notification 발송 — **Phase 1에서 같이 구현**.

```swift
func switchSearchProvider(to type: LBSProviderType) {
    UserDefaults.standard.set(type.rawValue, forKey: "search_provider")
    searchProviderType = type
    (search, geocoding) = Self.makeSearchServices(for: type)
    NotificationCenter.default.post(name: .lbsSearchProviderChanged, object: nil)  // ← 추가
}
```

**검증**: 개발자 메뉴에서 Kakao↔Apple 전환 후 홈 화면 카테고리 즉시 변경 확인

---

## 회귀 테스트

전체 작업 완료 후 아래 항목이 기존과 동일하게 동작하는지 확인.

| 항목 | 확인 방법 | 깨질 수 있는 원인 |
|------|----------|-----------------|
| 키워드 검색 결과 표시 | 검색창에 "스타벅스" 입력 → 결과 목록 정상 표시 | LBSServiceProvider 분리 후 search 서비스 잘못 연결 |
| 카테고리(주변검색) 결과 표시 | 홈 화면 카테고리 탭 → 결과 목록 정상 표시 | 동일 |
| 자동차 경로 계산 | 출발지/목적지 설정 → 경로 표시 | route 서비스 잘못 연결 |
| 도보 경로 계산 | 도보 모드로 경로 계산 | 동일 |
| 즐겨찾기 정상 동작 | 장소 즐겨찾기 추가/삭제 → 홈 화면 반영 | SettingsViewModel 변경 여파 |
| 최근 검색 정상 동작 | 검색 후 최근검색 목록 표시 | 동일 |
| 앱 첫 실행 (신규 설치) | 기존 `lbs_provider` 키 없는 상태 → searchProvider=Kakao, routeProvider=Apple 기본값 적용 | init 기본값 설정 오류 |
| 앱 업데이트 (마이그레이션) | 기존 `lbs_provider` 키 있는 상태 → route_provider만 인계, search_provider=Kakao | 마이그레이션 로직 버그 |
| 앱 재시작 후 provider 설정 유지 | 개발자 메뉴에서 경로 제공자 변경 → 앱 재시작 → 설정 유지 확인 | UserDefaults 키 변경으로 설정 초기화 |

---

## 주의사항

- Phase 1 완료 전에 Phase 3 진행 불가 (ViewModel이 새 Provider 타입 참조)
- `lbsProviderFallbackActivated` Notification을 다른 파일에서 구독하는 곳이 있다면 이름 변경 시 같이 수정 필요 — 코드베이스 전체 검색 필요
- FallbackGeocodingService도 동일한 패턴이면 Notification 추가 검토 (geocoding 429는 UX 임팩트 작아서 우선순위 낮음)
