# 홈 화면 드로어 — 개발 계획서

## 1. 개요

### 배경
PRD 7.1에서 홈 화면 하단을 **3단계(최소/중간/전체) 드래그 가능한 드로어(Bottom Sheet)**로 정의했으나, 현재 구현은 고정 높이 `bottomPanel` UIView로 되어 있어 사용자가 드래그로 높이를 조절할 수 없다.

### 목표
- 홈 화면 하단에 **커스텀 드로어** 구현 (HomeVC의 child view controller)
- 3단계 detent (최소/중간/전체) + UIPanGestureRecognizer 드래그
- 즐겨찾기 + 최근 검색을 드로어 내부에서 표시

### 구현 방식 선택 근거
UISheetPresentationController(modal present 방식)는 HomeVC가 nav stack에서 가려질 때 드로어가 presentation 계층에 의존하여 불필요한 숨김/복귀 동작이 발생한다. **드로어를 HomeVC의 subview(child VC)로 직접 포함**시키면 이러한 제약 없이, HomeVC의 뷰 계층에서 자연스럽게 동작한다.

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
│           │      │           │      │ ── grab ──│  ← 핸들 바
│           │      │  지 도    │      │ ⭐ 즐겨찾기 │
│  지 도    │      │  (중간)   │      │ 🏠🏢⭐...  │
│  (넓음)   │      │           │      │ 🕐 최근검색 │
│           │      ├───────────┤      │ 📍 강남역  │
│           │      │ ── grab ──│      │ 📍 스타벅스 │
├───────────┤      │ ⭐ 즐겨찾기 │      │ 📍 이마트  │
│ ── grab ──│      │ 🏠🏢⭐... │      │ 📍 ...    │
│ ⭐ 🏠 🏢  │      │ 🕐 최근검색 │      │           │
│ 🕐 강남역 │      │ 📍 강남역  │      └───────────┘
└───────────┘      │ 📍 스타벅스 │
                   └───────────┘
  200pt 고정         ~50% 화면         검색바 바로 아래까지
```

**개선사항:**
- child view controller 방식 — HomeVC의 뷰 계층에 직접 포함
- UIPanGestureRecognizer 기반 3단계 detent 전환
- 커스텀 핸들 바로 드래그 어포던스 제공
- 스프링 애니메이션으로 detent 스냅
- 컬렉션뷰 스크롤과 드로어 드래그 자동 연동

---

## 3. 아키텍처

### 3.1 컴포넌트 구조

```
┌─────────────────────────────────────────────────────────────┐
│                      AppCoordinator                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              UINavigationController                    │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │            HomeViewController                    │  │  │
│  │  │                                                 │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  MapViewController (child VC, index: 0)    │  │  │  │
│  │  │  │  - 전체 화면 지도                           │  │  │  │
│  │  │  │  - 현재 위치 마커                           │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  │                                                 │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  검색 바 + 설정 버튼 (subview, 상단 고정)    │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  │                                                 │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  HomeDrawerViewController (child VC)       │  │  │  │
│  │  │  │  - addChild()로 HomeVC에 포함               │  │  │  │
│  │  │  │  - 하단 고정, 높이만 변경                    │  │  │  │
│  │  │  │  - UIPanGestureRecognizer                  │  │  │  │
│  │  │  │                                            │  │  │  │
│  │  │  │  ┌────────────────────────────────────┐    │  │  │  │
│  │  │  │  │  핸들 바 (드래그 영역)               │    │  │  │  │
│  │  │  │  ├────────────────────────────────────┤    │  │  │  │
│  │  │  │  │  UICollectionView                  │    │  │  │  │
│  │  │  │  │  - Section 0: 즐겨찾기 (수평 스크롤) │    │  │  │  │
│  │  │  │  │  - Section 1: 최근 검색 (수직 리스트) │    │  │  │  │
│  │  │  │  └────────────────────────────────────┘    │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
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
    │       └──→ 사용자 탭 → onFavoriteTapped → HomeVC → AppCoordinator
    │                                                        │
    │                                                        ▼
    │                                                showRoutePreviewForFavorite()
    │
    └── recentSearches: CurrentValueSubject<[SearchHistory], Never>
            │
            ├──→ HomeDrawerVC (subscribe → collectionView.reloadData())
            │
            └──→ 사용자 탭 → onRecentSearchTapped → HomeVC → AppCoordinator
                                                                 │
                                                                 ▼
                                                     showRoutePreviewForHistory()
```

### 3.3 콜백 체인 (변경 없음)

```
HomeDrawerVC.onFavoriteTapped
    │
    ▼
HomeVC.onFavoriteTapped   ←── AppCoordinator에서 설정 (기존 코드 그대로)
    │
    ▼
AppCoordinator.showRoutePreviewForFavorite()
```

> **핵심**: AppCoordinator의 콜백 설정 코드는 변경하지 않는다.
> HomeVC가 내부적으로 드로어의 콜백을 자신의 콜백으로 전달(forward)한다.

---

## 4. 화면 전환 시 드로어 동작

### 4.1 동작 원리

드로어는 HomeVC의 **child view controller**(subview)이므로, HomeVC의 뷰 계층에 포함된다. nav stack에서 HomeVC가 가려지더라도 드로어의 상태(높이, detent)는 그대로 유지되며, HomeVC가 다시 보이면 마지막 상태로 자연스럽게 복귀한다.

```
┌──────────────────────────────────────────────────────────────────┐
│                     UINavigationController                        │
│                                                                  │
│  [HomeVC + Drawer] ──push──→ [RoutePreviewVC] ──push──→ [NavVC] │
│                                                                  │
│  HomeVC가 nav stack에 남아있으므로 Drawer 상태가 보존됨              │
│  pop 시 HomeVC + Drawer가 마지막 상태 그대로 다시 보임               │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 시나리오별 동작

```
시나리오                         │ 드로어 동작           │ 이유
─────────────────────────────────┼───────────────────────┼──────────────────
경로 미리보기 (push)              │ HomeVC와 함께 가려짐   │ nav stack에서 뒤로 밀림
경로 미리보기에서 복귀 (pop)       │ 마지막 상태 그대로 복귀 │ HomeVC 뷰 계층에 포함
검색 VC (fullScreen present)     │ 가려짐               │ fullScreen이 위에 표시
검색 VC 닫기 (dismiss)           │ 마지막 상태로 다시 보임 │ HomeVC 노출됨
네비게이션 (push)                │ HomeVC와 함께 가려짐   │ nav stack에서 뒤로 밀림
네비게이션 종료 (pop)             │ 마지막 상태 그대로 복귀 │ HomeVC 뷰 계층에 포함
```

> **장점**: 드로어 상태(detent 높이)가 항상 보존됨. 별도 lifecycle 관리 불필요.

---

## 5. Detent 설계

### 5.1 3단계 높이 다이어그램

```
     ┌─────────────────────────────┐  ← view.top
     │  🔍 여기서 검색      ⚙️      │  safeArea.top + 8pt
     │  (48pt)                     │
  ───├─────────────────────────────┤── 검색바 하단 = 드로어 최대 top 경계
     │                             │
     │                             │  ← [전체] drawerTop = 검색바 하단 + 8pt
     │                             │
     │         가용 영역             │
     │                             │  ← [중간] drawerTop = 화면 50%
     │                             │
     │                             │
     │                             │
  ───├─────────────────────────────┤── [최소] drawerTop = view.bottom - 200pt
     │       드로어 (최소)           │
     │         200pt               │
  ───└─────────────────────────────┘── view.bottom
```

### 5.2 높이 계산

```swift
enum DrawerDetent: CaseIterable {
    case small, medium, large

    func height(in view: UIView) -> CGFloat {
        let safeTop = view.safeAreaInsets.top
        let searchBarBottom = safeTop + 8 + 48 + 8  // safeArea + spacing + searchBar + spacing
        let maxHeight = view.bounds.height - searchBarBottom

        switch self {
        case .small:  return 200
        case .medium: return view.bounds.height * 0.5
        case .large:  return maxHeight
        }
    }
}
```

### 5.3 드래그 → 스냅 로직

```
드래그 시작 (began)
    │  panStartHeight 기록
    ▼
드래그 중 (changed)
    │  newHeight = panStartHeight - translation.y
    │  clamp(minHeight, maxHeight)
    │  heightConstraint.constant = newHeight
    ▼
드래그 종료 (ended)
    │  velocity 확인
    │  ├── velocity > threshold (빠른 스와이프) → 방향에 따라 다음/이전 detent
    │  └── velocity <= threshold → 가장 가까운 detent에 스냅
    ▼
스프링 애니메이션으로 target detent 높이에 스냅
    damping: 0.8, velocity: 0.5, duration: 0.35
```

---

## 6. 드래그 & 스크롤 연동

### 6.1 문제

컬렉션뷰 스크롤과 드로어 드래그가 동시에 동작하면 충돌이 발생한다. 이를 해결하기 위한 규칙:

```
[small / medium detent에서]
    │
    ├── 컬렉션뷰 contentOffset.y == 0 (최상단)
    │   ├── 위로 드래그 → 드로어 확장 (스크롤 비활성)
    │   └── 아래로 드래그 → 드로어 축소 (스크롤 비활성)
    │
    └── 컬렉션뷰 contentOffset.y > 0 (스크롤 중)
        └── 스크롤만 동작 (드로어 높이 고정)

[large detent에서]
    │
    ├── 컬렉션뷰 contentOffset.y == 0 (최상단)
    │   └── 아래로 드래그 → 드로어 축소 (스크롤 비활성)
    │
    └── 컬렉션뷰 contentOffset.y > 0
        └── 스크롤만 동작 (드로어 높이 고정)
```

### 6.2 구현 방식

```swift
// UIPanGestureRecognizer는 드로어 전체 뷰에 추가
// UIGestureRecognizerDelegate로 스크롤뷰와 동시 인식 설정

func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
) -> Bool {
    return other == collectionView.panGestureRecognizer
}

// 드래그 핸들러에서 분기:
// - collectionView가 최상단이면 → 드로어 높이 변경
// - collectionView가 스크롤 중이면 → 드로어 드래그 무시
```

---

## 7. 구현 상세

### 7.1 신규 파일: `HomeDrawerViewController.swift`

**위치**: `Navigation/Navigation/Feature/Home/HomeDrawerViewController.swift`

**HomeViewController에서 이동할 코드:**

| 코드 | HomeVC 원본 위치 | 설명 |
|------|-----------------|------|
| `HomeSection` enum | 8~11행 | 섹션 정의 |
| `collectionView` 프로퍼티 | 76~87행 | CompositionalLayout + 셀 등록 |
| `createCompositionalLayout()` | 221~231행 | 레이아웃 팩토리 |
| `createFavoritesSection()` | 233~249행 | 즐겨찾기 수평 스크롤 레이아웃 |
| `createRecentSearchesSection()` | 252~267행 | 최근 검색 수직 리스트 레이아웃 |
| `UICollectionViewDataSource` ext | 373~433행 | 데이터소스 전체 |
| `UICollectionViewDelegate` ext | 437~521행 | 딜리게이트 전체 (탭, 컨텍스트메뉴, 편집) |
| `HomeSectionHeaderView` class | 525~572행 | 섹션 헤더 뷰 |
| Combine 바인딩 (CombineLatest) | 292~298행 | favorites + recentSearches → reloadData |

**구조:**

```swift
final class HomeDrawerViewController: UIViewController {

    // MARK: - Detent
    enum DrawerDetent: CaseIterable {
        case small, medium, large
        func height(in view: UIView) -> CGFloat { ... }
    }

    // MARK: - Sections
    private enum HomeSection: Int, CaseIterable {
        case favorites = 0
        case recentSearches = 1
    }

    // MARK: - UI
    private let handleBar: UIView = { ... }()
    private lazy var collectionView: UICollectionView = { ... }()

    // MARK: - Drag State
    private var currentDetent: DrawerDetent = .small
    private var panStartHeight: CGFloat = 0
    var heightConstraint: NSLayoutConstraint!       // HomeVC에서 설정

    // MARK: - Properties
    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks
    var onFavoriteTapped: ((FavoritePlace) -> Void)?
    var onRecentSearchTapped: ((SearchHistory) -> Void)?

    // MARK: - Init
    init(viewModel: HomeViewModel) { ... }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        setupUI()
        setupPanGesture()
        bindViewModel()
    }

    // MARK: - Drag
    private func setupPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // began: panStartHeight 기록
        // changed: 높이 업데이트 (clamp)
        // ended: velocity 기반 target detent → 스프링 애니메이션 스냅
    }

    func snapToDetent(_ detent: DrawerDetent, animated: Bool = true) {
        currentDetent = detent
        let targetHeight = detent.height(in: view.superview ?? view)
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0,
                          usingSpringWithDamping: 0.8,
                          initialSpringVelocity: 0.5) { ... }
        } else {
            heightConstraint.constant = targetHeight
        }
    }

    // MARK: - Layout
    private func createCompositionalLayout() -> UICollectionViewCompositionalLayout { ... }
    private func createFavoritesSection() -> NSCollectionLayoutSection { ... }
    private func createRecentSearchesSection() -> NSCollectionLayoutSection { ... }
}

// MARK: - UIGestureRecognizerDelegate
extension HomeDrawerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) -> Bool { ... }
}

// MARK: - UICollectionViewDataSource
extension HomeDrawerViewController: UICollectionViewDataSource { ... }

// MARK: - UICollectionViewDelegate
extension HomeDrawerViewController: UICollectionViewDelegate { ... }

// MARK: - HomeSectionHeaderView
final class HomeSectionHeaderView: UICollectionReusableView { ... }
```

### 7.2 수정 파일: `HomeViewController.swift`

**제거할 코드:**
- `HomeSection` enum
- `bottomPanel` 프로퍼티 + 관련 제약 조건
- `collectionView` 프로퍼티
- `bottomPanelHeightConstraint` 프로퍼티
- `setupBottomPanel()` 메서드
- `updateBottomPanel(hasFavorites:hasSearches:)` 메서드
- `createCompositionalLayout()` 메서드
- `createFavoritesSection()` 메서드
- `createRecentSearchesSection()` 메서드
- `UICollectionViewDataSource` extension 전체
- `UICollectionViewDelegate` extension 전체
- `HomeSectionHeaderView` 클래스
- `bindViewModel()` 내 `Publishers.CombineLatest` 구독
- `viewDidLoad()`에서 `setupBottomPanel()` 호출

**추가할 코드:**

```swift
// MARK: - Properties (추가)
private var homeDrawer: HomeDrawerViewController!

// MARK: - viewDidLoad (수정)
override func viewDidLoad() {
    super.viewDidLoad()
    setupMapChild()
    setupSearchBar()
    setupSettingsButton()
    setupDrawer()          // setupBottomPanel() → setupDrawer()로 교체
    setupAccessibility()
    bindViewModel()
    handleInitialPermission()
}

// MARK: - Drawer Setup (추가)
private func setupDrawer() {
    let drawer = HomeDrawerViewController(viewModel: viewModel)
    self.homeDrawer = drawer

    // 콜백 전달
    drawer.onFavoriteTapped = { [weak self] fav in self?.onFavoriteTapped?(fav) }
    drawer.onRecentSearchTapped = { [weak self] h in self?.onRecentSearchTapped?(h) }

    // Child VC로 추가
    addChild(drawer)
    view.addSubview(drawer.view)
    drawer.view.translatesAutoresizingMaskIntoConstraints = false

    let heightConstraint = drawer.view.heightAnchor.constraint(equalToConstant: 200)
    drawer.heightConstraint = heightConstraint

    NSLayoutConstraint.activate([
        drawer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        drawer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        drawer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        heightConstraint,
    ])

    drawer.didMove(toParent: self)
}
```

**수정될 `bindViewModel()`:**
```swift
private func bindViewModel() {
    // authStatus 구독만 유지 (드로어 관련 CombineLatest 제거)
    viewModel.authStatus
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
            self?.handleAuthStatusChange(status)
        }
        .store(in: &cancellables)
}
```

### 7.3 AppCoordinator.swift — 변경 없음

기존 콜백 설정이 그대로 동작:

```swift
// start() 내부 — 변경 없음
homeVC.onFavoriteTapped = { [weak self] favorite in
    self?.showRoutePreviewForFavorite(favorite)
}
homeVC.onRecentSearchTapped = { [weak self] history in
    self?.showRoutePreviewForHistory(history)
}
```

---

## 8. 드로어 뷰 레이아웃

```
HomeDrawerViewController.view
├── layer.cornerRadius = Theme.CornerRadius.large (상단 모서리만)
├── layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
├── backgroundColor = Theme.Colors.background (0.95 alpha)
├── shadow (기존 bottomPanel과 동일)
│
├── handleBar (UIView)
│   ├── 36pt × 4pt, 중앙 정렬
│   ├── cornerRadius = 2
│   ├── backgroundColor = Theme.Colors.separator
│   └── topAnchor = view.top + 8pt
│
└── collectionView (UICollectionView)
    ├── topAnchor = handleBar.bottom + 8pt
    ├── leading/trailing = view
    ├── bottomAnchor = view.safeAreaLayoutGuide.bottom
    ├── backgroundColor = .clear
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

## 9. 엣지 케이스

### 9.1 데이터 새로고침
- `HomeVC.viewWillAppear`에서 `viewModel.loadHomeData()` 호출 (기존 유지)
- viewModel이 `favorites`/`recentSearches` subject를 업데이트
- HomeDrawerVC의 Combine 구독이 `collectionView.reloadData()` 트리거

### 9.2 빈 상태 (데이터 없음)
- 즐겨찾기 0개 + 최근 검색 0개일 때
- collectionView가 비어있는 상태로 표시
- small detent(200pt)에서 핸들 바만 보임

### 9.3 컨텍스트 메뉴 (즐겨찾기 편집/삭제)
- `showFavoriteEditAlert`가 HomeDrawerVC 위에 alert을 present
- `viewModel.deleteFavorite()` → `loadHomeData()` → Combine → reloadData

### 9.4 화면 회전 / Safe Area 변경
- `viewDidLayoutSubviews()`에서 현재 detent의 높이를 재계산
- 회전 시 medium/large detent 높이가 달라지므로 재스냅 필요

### 9.5 드래그 중 빠른 탭 (즐겨찾기/최근 검색)
- 드래그 제스처가 `.began` 상태가 아니면 탭 이벤트 정상 전달
- UIGestureRecognizerDelegate에서 동시 인식 허용

---

## 10. 파일 변경 요약

```
Navigation/Navigation/Feature/Home/
├── HomeDrawerViewController.swift  ← 🆕 신규 생성
│   - DrawerDetent enum (3단계 높이)
│   - 핸들 바 + 컬렉션뷰
│   - UIPanGestureRecognizer + 스냅 로직
│   - UICollectionViewDataSource/Delegate
│   - HomeSectionHeaderView
│
├── HomeViewController.swift        ← ✏️ 대폭 수정
│   - bottomPanel 관련 코드 모두 제거
│   - setupDrawer() 추가 (child VC 방식)
│   - bindViewModel() 간소화
│
├── HomeViewModel.swift             ← 변경 없음
├── FavoriteCell.swift              ← 변경 없음
└── RecentSearchCell.swift          ← 변경 없음

Navigation/Navigation/Coordinator/
└── AppCoordinator.swift            ← 변경 없음
```

---

## 11. 검증 방법

### 11.1 기능 테스트

| # | 테스트 항목 | 예상 결과 |
|---|-----------|----------|
| 1 | 앱 실행 후 홈 화면 | 드로어가 200pt(최소) 높이로 표시, 핸들 바 보임 |
| 2 | 핸들 바 위로 드래그 (최소→중간) | 화면 50%까지 확장, 스프링 스냅 |
| 3 | 계속 위로 드래그 (중간→전체) | 검색바 바로 아래까지 확장 |
| 4 | 아래로 드래그 (전체→최소) | 200pt로 축소, 스프링 스냅 |
| 5 | 빠른 스와이프 위로 | velocity 감지 → 바로 다음 detent로 스냅 |
| 6 | 빠른 스와이프 아래로 | velocity 감지 → 바로 이전 detent로 스냅 |
| 7 | 최소 높이에서 리스트 위로 스크롤 | 드로어 먼저 확장 → 전체에서 리스트 스크롤 |
| 8 | 전체 높이에서 리스트 아래로 스크롤 (top에서) | 드로어 축소 |
| 9 | 즐겨찾기 탭 | 경로 미리보기 화면으로 이동 |
| 10 | 최근 검색 탭 | 경로 미리보기 화면으로 이동 |
| 11 | 즐겨찾기 롱프레스 | 컨텍스트 메뉴 (편집/삭제) 표시 |

### 11.2 화면 전환 테스트

| # | 시나리오 | 예상 결과 |
|---|---------|----------|
| 1 | 즐겨찾기 탭 → 경로 미리보기 → 뒤로 | 드로어 마지막 detent 유지, 데이터 보존 |
| 2 | 검색바 탭 → 검색 VC → 취소 | 드로어 마지막 detent 유지 |
| 3 | 네비게이션 시작 → 종료 → 홈 복귀 | 드로어 마지막 detent 유지 |
| 4 | 가상 주행 시작 → 종료 → 홈 복귀 | 드로어 마지막 detent 유지 |

### 11.3 빌드 검증
```bash
xcodebuild build \
  -project Navigation.xcodeproj \
  -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet
```
