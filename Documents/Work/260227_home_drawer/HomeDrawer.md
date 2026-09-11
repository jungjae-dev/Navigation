# 홈 화면 드로어 — 개발 계획서

## 1. 개요

### 배경
PRD 7.1에서 홈 화면 하단을 **3단계(최소/중간/전체) 드래그 가능한 드로어(Bottom Sheet)**로 정의했으나, 현재 구현은 고정 높이 `bottomPanel` UIView로 되어 있어 사용자가 드래그로 높이를 조절할 수 없다.

### 목표
- 홈 화면 하단에 **UISheetPresentationController 기반 드로어** 구현
- 3단계 custom detent (최소/중간/전체) 드래그
- 즐겨찾기 + 최근 검색을 드로어 내부에서 표시
- 검색 결과 드로어와 동일한 컨셉으로 통일

### 구현 방식 선택 근거
**UISheetPresentationController(modal present 방식)**를 사용한다. 검색 결과 드로어도 동일한 방식이므로, 홈 드로어와 통일하여 일관된 UX를 제공한다. AppCoordinator가 드로어의 lifecycle(present/dismiss)을 관리하며, 화면 전환 시 명시적으로 dismiss → re-present하는 패턴을 사용한다.

### 관련 문서
- [PRD.md](../PRD.md) — 7.1 메인 화면, 7.2-D 드로어 높이 3단계
- [TechSpec.md](../TechSpec.md) — 3.7 검색 결과 드로어 & 마커-리스트 연동
- [Architecture.md](../Architecture.md) — 프로젝트 폴더 구조, 서비스 레이어

---

## 2. 현재 구현 vs 목표 비교

### 현재 구현 (Before)

```
┌─────────────────────────────┐
│  🔍 여기서 검색      ⚙️      │  ← 검색 바 + 설정 버튼
├─────────────────────────────┤
│                             │
│                             │
│         [ 지 도 ]           │
│           📍                │  ← 현재 위치
│                             │
│                             │
├─────────────────────────────┤  ← bottomPanel (UIView, 고정 높이)
│  ⭐ 즐겨찾기                 │     - 드래그 불가
│  🏠 집  🏢 회사              │     - 높이 = 콘텐츠 기반 자동 계산
│  🕐 최근 검색                │     - UICollectionView 내장
│  📍 강남역                   │
└─────────────────────────────┘
```

**문제점:**
- `bottomPanel`은 `UIView`로 높이가 콘텐츠에 맞춰 고정됨
- 드래그 제스처 없음 → 사용자가 높이를 조절할 수 없음
- 핸들 바 없음 → 드로어임을 시각적으로 인지할 수 없음
- 3단계 전환 불가

### 목표 구현 (After)

```
[최소 높이]          [중간 높이]          [전체 높이]
┌───────────┐      ┌───────────┐      ┌───────────┐
│ 🔍    ⚙️   │      │ 🔍    ⚙️   │      │ 🔍    ⚙️   │  ← 검색바 항상 고정
├───────────┤      ├───────────┤      ├───────────┤
│           │      │           │      │ ── grab ──│  ← 시스템 grabber
│           │      │  지 도    │      │ ⭐ 즐겨찾기 │
│  지 도    │      │  (중간)   │      │ 🏠🏢⭐...  │
│  (넓음)   │      │           │      │ 🕐 최근검색 │
│           │      ├───────────┤      │ 📍 강남역  │
│           │      │ ── grab ──│      │ 📍 스타벅스 │
├───────────┤      │ ⭐ 즐겨찾기 │      │ 📍 이마트  │
│ ── grab ──│      │ 🏠🏢⭐... │      │ 📍 ...    │
│ ⭐ 🏠 🏢  │      │ 🕐 최근검색 │      └───────────┘
│ 🕐 강남역 │      │ 📍 강남역  │
└───────────┘      │ 📍 스타벅스 │
                   └───────────┘
  200pt 고정     drawerMax * 0.5     검색바 바로 아래까지
```

**개선사항:**
- UISheetPresentationController 기반 — 검색 결과 드로어와 동일한 컨셉
- 3단계 custom detent (small/medium/large), 시스템 grabber 사용
- AppCoordinator가 드로어 lifecycle 관리 (present/dismiss)
- 지도 컨트롤 버튼이 detent 변경에 따라 자동 위치 조정
- 딤 처리 없음, 드로어 뒤 터치 패스쓰루

---

## 3. 아키텍처

### 3.1 컴포넌트 구조

```
┌─────────────────────────────────────────────────────────────┐
│                      AppCoordinator                          │
│  - UISheetPresentationControllerDelegate                    │
│  - 홈 드로어 / 검색 결과 드로어 lifecycle 관리                  │
│  - configureSheetDetents(for:) — 통합 detent 설정             │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              UINavigationController                    │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │            HomeViewController                    │  │  │
│  │  │  - 지도 (MapViewController, child VC)            │  │  │
│  │  │  - 검색 바 + 설정 버튼 (subview, 상단 고정)        │  │  │
│  │  │  - 나침반 (MKCompassButton)                      │  │  │
│  │  │  - 지도 컨트롤 버튼 (MapControlButtonsView)       │  │  │
│  │  │  - updateMapControlBottomOffset(_:) 제공           │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                                                        │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  HomeDrawerViewController (modal present)        │  │  │
│  │  │  - UISheetPresentationController로 표시            │  │  │
│  │  │  - isModalInPresentation = true (dismiss 방지)    │  │  │
│  │  │  - UICollectionView (즐겨찾기 + 최근 검색)         │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 데이터 흐름

```
HomeViewModel (Combine)
    │
    ├── favorites: CurrentValueSubject<[FavoritePlace], Never>
    │       │
    │       ├──→ HomeDrawerVC (subscribe → collectionView.reloadData())
    │       │
    │       └──→ 사용자 탭 → onFavoriteTapped → AppCoordinator
    │                                                │
    │                                                ▼
    │                                    dismissHomeDrawer()
    │                                    showRoutePreviewForFavorite()
    │
    └── recentSearches: CurrentValueSubject<[SearchHistory], Never>
            │
            ├──→ HomeDrawerVC (subscribe → collectionView.reloadData())
            │
            └──→ 사용자 탭 → onRecentSearchTapped → AppCoordinator
                                                         │
                                                         ▼
                                             dismissHomeDrawer()
                                             showRoutePreviewForHistory()
```

### 3.3 콜백 체인

```
HomeDrawerVC.onFavoriteTapped
    │
    ▼
AppCoordinator (직접 연결, HomeVC 경유 없음)
    │
    ▼
dismissHomeDrawer() → showRoutePreviewForFavorite()
```

> **핵심**: AppCoordinator가 HomeDrawerVC의 콜백을 직접 설정한다. HomeVC는 드로어 관련 콜백을 갖지 않는다.

---

## 4. 화면 전환 시 드로어 동작

### 4.1 동작 원리

드로어는 **UISheetPresentationController 기반 modal present**이므로, 화면 전환 시 AppCoordinator가 명시적으로 dismiss/re-present를 관리한다. `isModalInPresentation = true`로 사용자의 드래그 dismiss를 방지한다.

```
┌──────────────────────────────────────────────────────────────────┐
│                     UINavigationController                        │
│                                                                  │
│  [HomeVC] ──present──→ [HomeDrawerVC] (sheet)                    │
│                                                                  │
│  화면 전환 시:                                                     │
│  1. dismissHomeDrawer() → homeDrawer = nil                       │
│  2. 다른 화면으로 이동 (push/present)                                │
│  3. 복귀 시 presentHomeDrawer() → 새 인스턴스 생성 + present        │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 시나리오별 동작

```
시나리오                         │ 드로어 동작                    │ 이유
─────────────────────────────────┼───────────────────────────────┼──────────────────
앱 시작 (start())                │ medium detent로 present       │ DispatchQueue.main.async
검색바 탭                         │ dismiss → SearchVC present    │ showSearch()
검색 취소                         │ SearchVC dismiss → re-present │ onDismiss 콜백
검색 결과 선택                     │ SearchVC dismiss → 결과 드로어  │ onSearchResults 콜백
검색 결과 드로어 drag-dismiss       │ clean up → re-present        │ presentationControllerDidDismiss
즐겨찾기/최근검색 탭                │ dismiss → 경로 미리보기        │ onFavoriteTapped/onRecentSearchTapped
경로 미리보기 → 뒤로               │ returnMapToHome → re-present │ dismissRoutePreview()
설정 진입                         │ dismiss → push SettingsVC     │ showSettings()
설정 → 뒤로                       │ pop → re-present             │ onDismiss 콜백
네비게이션 시작                    │ dismiss (animated: false)     │ handleCarPlayNavigationStarted
네비게이션 종료                    │ returnMapToHome → re-present │ cleanUpNavigationUI
```

---

## 5. Detent 설계

### 5.1 3단계 높이 다이어그램

```
     ┌─────────────────────────────┐  ← view.top
     │  🔍 여기서 검색      ⚙️      │  safeArea.top + 8pt
     │  (48pt)                     │
  ───├─────────────────────────────┤── 검색바 하단 + 8pt = 드로어 최대 top 경계
     │                             │
     │                             │  ← [전체] drawerMaxHeight
     │                             │
     │         가용 영역             │
     │                             │  ← [중간] drawerMaxHeight * 0.5
     │                             │
     │                             │
     │                             │
  ───├─────────────────────────────┤── [최소] 200pt
     │       드로어 (최소)           │
     │         200pt               │
  ───└─────────────────────────────┘── safe area bottom
```

### 5.2 높이 계산 (AppCoordinator)

```swift
// Detent Identifiers (커스텀 — 시스템 identifier와 충돌 방지)
private static let smallDetentId = UISheetPresentationController.Detent.Identifier("small")
private static let mediumDetentId = UISheetPresentationController.Detent.Identifier("drawerMedium")
private static let largeDetentId = UISheetPresentationController.Detent.Identifier("drawerLarge")

/// Top map inset: 검색바 하단 (safeArea + spacing + searchBarHeight + spacing)
private func mapTopInset(in containerView: UIView) -> CGFloat {
    return containerView.safeAreaInsets.top + Theme.Spacing.sm + 48 + Theme.Spacing.sm
}

/// 드로어 최대 높이 (검색바 하단 + 마진 아래)
private func drawerMaxHeight(in containerView: UIView) -> CGFloat {
    let searchBarBottom = mapTopInset(in: containerView)
    return containerView.bounds.height - searchBarBottom - Theme.Spacing.sm
}

/// Detent별 높이 계산
private func drawerHeight(for detentId: ..., in containerView: UIView) -> CGFloat {
    switch detentId {
    case Self.smallDetentId:    return 200
    case Self.mediumDetentId:   return drawerMaxHeight(in: containerView) * 0.5
    default:                    return drawerMaxHeight(in: containerView)
    }
}
```

### 5.3 통합 Sheet 설정 (홈 드로어 + 검색 결과 드로어 공유)

```swift
private func configureSheetDetents(for viewController: UIViewController) {
    guard let sheet = viewController.sheetPresentationController else { return }

    sheet.detents = [smallDetent, mediumDetent, largeDetent]  // custom detent 3개
    sheet.selectedDetentIdentifier = Self.mediumDetentId       // 초기: 중간
    sheet.prefersGrabberVisible = true                         // 시스템 grabber
    sheet.largestUndimmedDetentIdentifier = Self.largeDetentId // 딤 처리 없음
    sheet.prefersScrollingExpandsWhenScrolledToEdge = false    // 스크롤-detent 전환은 DrawerScrollHelper가 수동 처리
    sheet.delegate = self                                      // detent 변경 감지
}
```

---

## 6. 지도 연동

### 6.1 지도 컨트롤 버튼 위치 업데이트

지도 컨트롤 버튼(현재 위치, 지도 모드)은 드로어 detent에 따라 위치가 변경된다.

```
HomeViewController.mapControlBottomConstraint
    기준: view.safeAreaLayoutGuide.bottomAnchor
    값:   -(drawerHeight + Theme.Spacing.md)
```

### 6.2 지도 인셋 (Map Insets)

드로어 높이에 따라 지도의 유효 콘텐츠 영역을 동적으로 조정한다. `mapView.layoutMargins`를 사용하여 상단(검색바 아래)과 하단(드로어 높이)만큼 인셋을 적용한다.

```swift
// MapViewController
func updateMapInsets(top: CGFloat, bottom: CGFloat) {
    mapView.layoutMargins = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
}

func resetMapInsets() {
    mapView.layoutMargins = .zero
}
```

이로 인해 `fitAnnotations`/`fitPolyline` 등에서 사용하던 하드코딩 padding(top: 80, bottom: 200)을 줄이고(40pt), layoutMargins가 실제 오프셋을 담당하도록 변경했다.

```
HomeViewController.updateMapInsets(top:bottom:)
    └── MapViewController.updateMapInsets(top:bottom:)
            └── mapView.layoutMargins = UIEdgeInsets(top: mapTopInset, left: 0, bottom: drawerHeight, right: 0)
```

### 6.3 업데이트 시점

| 시점 | 호출 위치 | 업데이트 항목 |
|------|----------|-------------|
| 드로어 최초 present | `presentHomeDrawer()` / `showSearchResults()` | 버튼 위치 + 지도 인셋 |
| detent 변경 (드래그) | `sheetPresentationControllerDidChangeSelectedDetentIdentifier` | 버튼 위치 + 지도 인셋 |
| 경로 미리보기 전환 | `showRoutePreview()` | `resetMapInsets()` |

### 6.4 large detent 시 버튼 위치

large detent에서는 버튼이 너무 높이 올라가므로, medium 높이로 cap한다:

```swift
let effectiveDetent = (detentId == Self.largeDetentId) ? Self.mediumDetentId : detentId
let height = drawerHeight(for: effectiveDetent, in: containerView)
homeViewController.updateMapControlBottomOffset(height)
```

---

## 7. 구현 상세

### 7.1 HomeDrawerViewController.swift

**위치**: `Navigation/Navigation/Feature/Home/HomeDrawerViewController.swift`

콘텐츠만 담당하는 순수 VC. 드래그 detent 전환은 `DrawerScrollHelper`가 처리.

**구조:**

```swift
final class HomeDrawerViewController: UIViewController {

    // MARK: - Sections
    private enum HomeSection: Int, CaseIterable {
        case favorites = 0
        case recentSearches = 1
    }

    // MARK: - UI
    private lazy var collectionView: UICollectionView = {
        // ...
        cv.alwaysBounceVertical = false  // 스크롤 끝에서 불필요한 바운스 방지
        return cv
    }()

    // MARK: - Properties
    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks
    var onFavoriteTapped: ((FavoritePlace) -> Void)?
    var onRecentSearchTapped: ((SearchHistory) -> Void)?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        isModalInPresentation = true  // 드래그 dismiss 방지
        setupUI()
        bindViewModel()
    }

    // MARK: - Layout
    private func createCompositionalLayout() -> UICollectionViewCompositionalLayout { ... }
    private func createFavoritesSection() -> NSCollectionLayoutSection { ... }
    private func createRecentSearchesSection() -> NSCollectionLayoutSection { ... }
}

// MARK: - UICollectionViewDataSource
extension HomeDrawerViewController: UICollectionViewDataSource { ... }

// MARK: - UICollectionViewDelegate
extension HomeDrawerViewController: UICollectionViewDelegate {
    // ...

    // 스크롤 끝 도달 시 DrawerScrollHelper로 detent 전환
    func scrollViewWillEndDragging(_:withVelocity:targetContentOffset:) {
        DrawerScrollHelper.handleScrollEdgeTransition(
            scrollView: scrollView,
            velocity: velocity,
            sheet: sheetPresentationController
        )
    }
}

// MARK: - HomeSectionHeaderView
final class HomeSectionHeaderView: UICollectionReusableView { ... }
```

### 7.1.1 DrawerScrollHelper (공통 유틸리티)

**위치**: `Navigation/Navigation/Common/Util/DrawerScrollHelper.swift`

`prefersScrollingExpandsWhenScrolledToEdge = false`로 설정한 뒤, 스크롤이 끝(top/bottom)에 도달했을 때 velocity 기반으로 detent를 수동 전환하는 헬퍼. HomeDrawerVC와 SearchResultDrawerVC가 공유한다.

```swift
enum DrawerScrollHelper {
    private static let detentOrder: [Detent.Identifier] = [
        .init("small"), .init("drawerMedium"), .init("drawerLarge")
    ]
    private static let velocityThreshold: CGFloat = 0.5

    /// 스크롤이 끝에 도달했을 때, 속도에 따라 드로어 detent를 전환
    static func handleScrollEdgeTransition(
        scrollView: UIScrollView,
        velocity: CGPoint,
        sheet: UISheetPresentationController?
    )
    // - 상단 도달 + 아래로 스와이프 → 이전(작은) detent로 축소
    // - 하단 도달 + 위로 스와이프 → 다음(큰) detent로 확장
}
```

**시스템 동작 대비 장점:**
- `prefersScrollingExpandsWhenScrolledToEdge = true`(시스템 기본)는 스크롤과 detent 확장이 동시에 발생하여 의도치 않은 전환이 잦음
- 수동 처리로 velocity threshold를 두어, 명시적인 스와이프 의도가 있을 때만 전환

### 7.2 HomeViewController.swift

드로어 관련 코드 없음. 지도 + 검색바 + 설정 버튼 + 지도 컨트롤 버튼만 관리.

**제거된 코드 (이전 child VC 방식 대비):**
- `homeDrawer` 프로퍼티
- `setupDrawer()` 메서드
- `onFavoriteTapped`, `onRecentSearchTapped` 콜백
- `updateMapControlPosition(for:)` 메서드

**제공하는 퍼블릭 인터페이스:**

```swift
// AppCoordinator가 detent 변경 시 호출
func updateMapControlBottomOffset(_ height: CGFloat) {
    UIView.animate(withDuration: 0.3) {
        self.mapControlBottomConstraint.constant = -(height + Theme.Spacing.md)
        self.view.layoutIfNeeded()
    }
}

// AppCoordinator가 detent 변경 시 호출 — 지도 인셋 업데이트
func updateMapInsets(top: CGFloat, bottom: CGFloat) {
    mapViewController.updateMapInsets(top: top, bottom: bottom)
}
```

### 7.3 AppCoordinator.swift — 드로어 lifecycle 관리

**추가된 프로퍼티:**

```swift
private var homeViewModel: HomeViewModel!
private var homeDrawer: HomeDrawerViewController?
private var currentDrawer: SearchResultDrawerViewController?
```

**주요 메서드:**

| 메서드 | 역할 |
|--------|------|
| `presentHomeDrawer()` | HomeDrawerVC 생성, 콜백 설정, configureSheetDetents, present, 지도 인셋 설정 |
| `dismissHomeDrawer(animated:completion:)` | 드로어 dismiss + homeDrawer = nil |
| `configureSheetDetents(for:)` | 통합 detent 설정 (홈/검색결과 공유) |
| `mapTopInset(in:)` | 검색바 하단 위치 계산 (지도 인셋 top + drawerMaxHeight 공용) |
| `drawerMaxHeight(in:)` | 드로어 최대 높이 계산 (mapTopInset 활용) |
| `drawerHeight(for:in:)` | detent ID별 높이 반환 |
| `dismissSearchResultDrawer(animated:completion:)` | 검색결과 드로어 dismiss + cleanup |

**UISheetPresentationControllerDelegate:**

```swift
extension AppCoordinator: UISheetPresentationControllerDelegate {

    // detent 변경 → 지도 버튼 위치 + 지도 인셋 업데이트
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_:) { ... }

    // 검색결과 드로어 drag-dismiss → 홈 드로어 re-present
    func presentationControllerDidDismiss(_:) { ... }
}
```

---

## 8. 검색 플로우 상세

```
홈 (homeDrawer sheet 표시)
  ↓ 검색바 탭
dismissHomeDrawer → present SearchVC (fullscreen, animated: false)
  ↓ 검색 취소
dismiss SearchVC → presentHomeDrawer()
  ↓ 검색 결과 선택
dismiss SearchVC → showSearchResults() (SearchResultDrawer sheet 표시)
  ↓ 결과 드로어 drag-dismiss
presentationControllerDidDismiss → cleanup → presentHomeDrawer()
  ↓ 결과 항목 선택
dismiss SearchResultDrawer → showRoutePreview → push RoutePreviewVC
  ↓ 뒤로가기
pop RoutePreviewVC → returnMapToHome() → presentHomeDrawer()
```

---

## 9. 드로어 뷰 레이아웃

```
HomeDrawerViewController.view (UISheetPresentationController가 관리)
├── backgroundColor = Theme.Colors.background
├── 시스템 grabber (prefersGrabberVisible = true)
│
└── collectionView (UICollectionView)
    ├── topAnchor = view.top + Theme.Spacing.lg (grabber 공간)
    ├── leading/trailing = view
    ├── bottomAnchor = view.safeAreaLayoutGuide.bottom
    ├── backgroundColor = .clear
    ├── alwaysBounceVertical = false
    │
    ├── Section 0: 즐겨찾기 (수평 스크롤)
    │   ├── 헤더: "⭐ 즐겨찾기" (36pt)
    │   └── 72×72pt 셀, orthogonalScrollingBehavior = .continuous
    │
    └── Section 1: 최근 검색 (수직 리스트)
        ├── 헤더: "🕐 최근 검색" (36pt)
        └── fullWidth × 52pt 셀
```

---

## 10. 엣지 케이스

### 10.1 데이터 새로고침
- `HomeVC.viewWillAppear`에서 `viewModel.loadHomeData()` 호출 (기존 유지)
- viewModel이 `favorites`/`recentSearches` subject를 업데이트
- HomeDrawerVC의 Combine 구독이 `collectionView.reloadData()` 트리거

### 10.2 빈 상태 (데이터 없음)
- 즐겨찾기 0개 + 최근 검색 0개일 때
- collectionView가 비어있는 상태로 표시
- small detent(200pt)에서 grabber만 보임

### 10.3 컨텍스트 메뉴 (즐겨찾기 편집/삭제)
- `showFavoriteEditAlert`가 HomeDrawerVC 위에 alert을 present
- `viewModel.deleteFavorite()` → `loadHomeData()` → Combine → reloadData

### 10.4 검색결과 드로어 drag-dismiss
- `isModalInPresentation = false` (기본값)이므로 아래로 내려서 dismiss 가능
- `presentationControllerDidDismiss` 델리게이트에서 cleanup 후 홈 드로어 re-present

### 10.5 홈 드로어 dismiss 방지
- `isModalInPresentation = true` 설정
- 사용자가 아래로 드래그해도 dismiss되지 않고 small detent까지만 축소

---

## 11. 파일 변경 요약

```
Navigation/Navigation/Feature/Home/
├── HomeDrawerViewController.swift  ← 콘텐츠 전용 VC
│   - HomeSection enum
│   - UICollectionView + CompositionalLayout (alwaysBounceVertical = false)
│   - UICollectionViewDataSource/Delegate
│   - scrollViewWillEndDragging → DrawerScrollHelper로 detent 전환
│   - ContextMenu (즐겨찾기 편집/삭제)
│   - HomeSectionHeaderView
│   - isModalInPresentation = true
│
├── HomeViewController.swift        ← 드로어 관련 코드 없음
│   - MapViewController (child VC)
│   - 검색 바 + 설정 버튼 (상단)
│   - MKCompassButton
│   - MapControlButtonsView (하단, safeArea 기준)
│   - updateMapControlBottomOffset(_:) 퍼블릭 메서드
│   - updateMapInsets(top:bottom:) 퍼블릭 메서드
│
├── MapControlButtonsView.swift     ← 변경 없음
├── HomeViewModel.swift             ← 변경 없음
├── FavoriteCell.swift              ← 변경 없음
└── RecentSearchCell.swift          ← 변경 없음

Navigation/Navigation/Common/Util/
└── DrawerScrollHelper.swift        ← 스크롤-detent 전환 공통 유틸리티
    - detentOrder: [small, drawerMedium, drawerLarge]
    - velocityThreshold: 0.5
    - handleScrollEdgeTransition(scrollView:velocity:sheet:)

Navigation/Navigation/Map/
└── MapViewController.swift         ← 지도 인셋 관리 추가
    - updateMapInsets(top:bottom:) — mapView.layoutMargins 설정
    - resetMapInsets() — mapView.layoutMargins = .zero
    - fitAnnotations/fitPolyline padding 축소 (80/200 → 40, layoutMargins가 오프셋 담당)

Navigation/Navigation/Coordinator/
└── AppCoordinator.swift            ← 드로어 lifecycle 관리 추가
    - NSObject 상속 (UISheetPresentationControllerDelegate)
    - homeViewModel, homeDrawer, currentDrawer 프로퍼티
    - presentHomeDrawer(), dismissHomeDrawer()
    - configureSheetDetents(for:) — 통합 detent 설정 (prefersScrollingExpandsWhenScrolledToEdge = false)
    - mapTopInset(in:) — 검색바 하단 위치 (인셋 + drawerMaxHeight 공용)
    - drawerMaxHeight(in:), drawerHeight(for:in:)
    - UISheetPresentationControllerDelegate 구현 (버튼 위치 + 지도 인셋 동시 업데이트)
    - 모든 화면 전환 메서드에서 drawer dismiss/present 처리
```

---

## 12. 검증 방법

### 12.1 기능 테스트

| # | 테스트 항목 | 예상 결과 |
|---|-----------|----------|
| 1 | 앱 실행 후 홈 화면 | 드로어가 medium detent로 표시, 시스템 grabber 보임 |
| 2 | grabber 위로 드래그 (중간→전체) | 검색바 바로 아래까지 확장 |
| 3 | grabber 아래로 드래그 (중간→최소) | 200pt로 축소 |
| 4 | 빠른 스와이프 위/아래 | 다음/이전 detent로 스냅 |
| 5 | 전체 높이에서 리스트 스크롤 | 스크롤 정상 동작 |
| 6 | 즐겨찾기 탭 | 드로어 dismiss → 경로 미리보기 화면으로 이동 |
| 7 | 최근 검색 탭 | 드로어 dismiss → 경로 미리보기 화면으로 이동 |
| 8 | 즐겨찾기 롱프레스 | 컨텍스트 메뉴 (편집/삭제) 표시 |
| 9 | 드로어 아래로 드래그 (dismiss 시도) | dismiss 안 됨 (isModalInPresentation) |
| 10 | 드로어 뒤 지도 터치 | 정상 동작 (딤 없음, 터치 패스쓰루) |
| 11 | 지도 컨트롤 버튼 | detent 변경 시 위치 연동 |

### 12.2 화면 전환 테스트

| # | 시나리오 | 예상 결과 |
|---|---------|----------|
| 1 | 즐겨찾기 탭 → 경로 미리보기 → 뒤로 | 홈 드로어 medium detent로 re-present |
| 2 | 검색바 탭 → 검색 VC → 취소 | 홈 드로어 medium detent로 re-present |
| 3 | 검색 → 결과 선택 → 결과 드로어 표시 | 검색결과 드로어 medium detent로 표시 |
| 4 | 검색결과 드로어 drag-dismiss | 홈 드로어 자동 re-present |
| 5 | 설정 → 뒤로 | 홈 드로어 medium detent로 re-present |
| 6 | 네비게이션 시작 → 종료 → 홈 복귀 | 홈 드로어 medium detent로 re-present |
| 7 | 가상 주행 시작 → 종료 → 홈 복귀 | 홈 드로어 medium detent로 re-present |

### 12.3 빌드 검증
```bash
cd Navigation
xcodebuild build \
  -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet
```
