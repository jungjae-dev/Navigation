# Phase 3: 홈 화면 구조 변경

## 목표

- HomeVC 상단의 검색바/설정 버튼을 HomeDrawer 헤더로 이동
- 드로어 높이(detent)를 safeArea top ~ safeArea bottom으로 조정
- 검색바 탭 -> 홈드로어 full 전환 -> SearchVC 모달 플로우 구현

## 작업 파일

### 수정

- `Feature/Home/HomeViewController.swift`
- `Feature/Home/HomeDrawerViewController.swift`
- `Coordinator/AppCoordinator.swift`

---

## 3-1. HomeViewController 변경

### 제거할 요소

```swift
// 삭제 대상
private let searchBarContainer: UIView      // 상단 검색바 컨테이너
private let searchIconImageView: UIImageView
private let searchLabel: UILabel
private let settingsButton: UIButton        // 설정 버튼
var onSearchBarTapped: (() -> Void)?        // -> HomeDrawer로 이동
var onSettingsTapped: (() -> Void)?         // -> HomeDrawer로 이동
```

### 변경 전 레이아웃

```
┌──────────────────────────────┐
│ [🔍 여기서 검색]        [⚙] │  safeArea top + 8
│                              │
│            지도               │
│  [🧭]                       │
│                     [📍][🗺]│
├── 드로어 ────────────────────┤
│  (최대높이 = 화면 - 검색바영역)│
└──────────────────────────────┘
```

### 변경 후 레이아웃

```
┌──────────────────────────────┐
│ (상태바)                     │
├─ safeArea top ───────────────┤
│                              │
│            지도               │
│  [🧭]                       │
│                     [📍][🗺]│
│                              │
├── 드로어 ────────────────────┤
│  (최대높이 = safeArea top)    │
├─ safeArea bottom ────────────┤
└──────────────────────────────┘
```

### drawerMaxHeight 계산 변경

```swift
// 변경 전
let safeAreaTop = view.safeAreaInsets.top
let searchBarArea = safeAreaTop + Theme.Spacing.sm + 48 + Theme.Spacing.sm
let drawerMaxHeight = containerHeight - searchBarArea - Theme.Spacing.sm - safeAreaBottom

// 변경 후
let safeAreaTop = view.safeAreaInsets.top
let safeAreaBottom = view.safeAreaInsets.bottom
let drawerMaxHeight = containerHeight - safeAreaTop - safeAreaBottom
```

### 나침반 위치 변경

```swift
// 변경 전: searchBarContainer 기준
compass.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: Theme.Spacing.sm)

// 변경 후: safeArea top 기준
compass.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm)
```

### mapControlBottomConstraint 업데이트 로직

```swift
// 기존 로직 유지, drawerMediumHeight 기준 cap만 재계산
drawerManager.onHeightChanged = { [weak self] height in
    guard let self else { return }
    let effectiveHeight = min(height, drawerMediumHeight)
    mapControlBottomConstraint.constant = -(effectiveHeight + Theme.Spacing.sm)
}
```

---

## 3-2. HomeDrawerViewController 변경

### 추가할 요소

```swift
// 신규 추가
private let headerView = DrawerHeaderView()
private let searchBarView = SearchBarView(placeholder: "여기서 검색")
private let settingsButton = DrawerIconButton(preset: .settings)

var onSearchBarTapped: (() -> Void)?    // HomeVC에서 이동
var onSettingsTapped: (() -> Void)?     // HomeVC에서 이동
```

### 변경 후 레이아웃

```
┌─────────────────────────────────────────┐
│  ┌─ DrawerHeaderView (44px) ──────────┐ │
│  │ [SearchBarView 40px]        [⚙ 32] │ │
│  └────────────────────────────────────┘ │
│  ─────────── separator ────────────────│
│                                  8px   │
│  ┌─ CollectionView ───────────────────┐ │
│  │  ★ 즐겨찾기         (SectionHeader) │ │
│  │  [72×72] [72×72] [72×72] 가로스크롤  │ │
│  │                                     │ │
│  │  🕐 최근 검색        (SectionHeader) │ │
│  │  [DrawerListCell] 장소명 / 주소      │ │
│  │  [DrawerListCell] 장소명 / 주소      │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### setupUI 변경

```swift
private func setupUI() {
    view.backgroundColor = Theme.Colors.background

    // 헤더 설정
    headerView.setCenterView(searchBarView)
    headerView.addRightAction(settingsButton)

    view.addSubview(headerView)
    view.addSubview(collectionView)

    NSLayoutConstraint.activate([
        // 헤더: 상단 고정
        headerView.topAnchor.constraint(equalTo: view.topAnchor),
        headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

        // 컬렉션뷰: 헤더 separator 아래
        collectionView.topAnchor.constraint(
            equalTo: headerView.bottomAnchor,
            constant: Theme.Drawer.Layout.contentTopPadding   // 8px
        ),
        collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])

    // 액션 연결
    searchBarView.onTapped = { [weak self] in
        self?.onSearchBarTapped?()
    }
    settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
}
```

---

## 3-3. AppCoordinator 변경

### 검색 플로우 변경

```swift
// 변경 전
homeViewController.onSearchBarTapped = { [weak self] in
    self?.presentSearchScreen()
}

// 변경 후
homeDrawerVC.onSearchBarTapped = { [weak self] in
    self?.handleSearchBarTapped()
}

private func handleSearchBarTapped() {
    // 1. 홈드로어를 full detent로 전환
    drawerManager.snapToDetent(id: "drawerLarge") { [weak self] in
        // 2. 완료 후 SearchVC 모달 표시
        self?.presentSearchScreen()
    }
}
```

### 검색 완료/취소 후 복귀

```swift
// SearchVC dismiss 후
private func handleSearchDismissed() {
    // 홈드로어를 medium detent로 복귀
    drawerManager.snapToDetent(id: "drawerMedium")
}
```

### detent 계산 변경

```swift
// 변경 전
let maxHeight = view.frame.height - safeAreaTop - searchBarArea - safeAreaBottom
let detents: [DrawerDetent] = [
    .absolute(200, id: "small"),
    .absolute(maxHeight * 0.5, id: "drawerMedium"),
    .absolute(maxHeight, id: "drawerLarge"),
]

// 변경 후
let maxHeight = view.frame.height - safeAreaTop - safeAreaBottom
let detents: [DrawerDetent] = [
    .absolute(200, id: "small"),
    .absolute(maxHeight * 0.5, id: "drawerMedium"),
    .absolute(maxHeight, id: "drawerLarge"),
]
```

### 설정 콜백 이동

```swift
// 변경 전
homeViewController.onSettingsTapped = { [weak self] in
    self?.presentSettings()
}

// 변경 후
homeDrawerVC.onSettingsTapped = { [weak self] in
    self?.presentSettings()
}
```

---

## 3-4. DrawerContainerManager 변경 (필요 시)

### snapToDetent 콜백 추가

검색바 탭 시 full 전환 완료를 감지하기 위해, 스냅 완료 콜백이 필요할 수 있다.

```swift
// 기존에 없다면 추가
func snapToDetent(id: String, completion: (() -> Void)? = nil) {
    // 해당 id의 detent 높이로 애니메이션
    // 완료 후 completion 호출
}
```

---

## 체크리스트

- [ ] HomeVC에서 searchBarContainer, settingsButton, 관련 콜백 제거
- [ ] HomeVC 나침반 제약조건을 safeArea top 기준으로 변경
- [ ] HomeVC drawerMaxHeight 계산을 safeArea 기준으로 변경
- [ ] HomeDrawerVC에 DrawerHeaderView + SearchBarView + 설정버튼 추가
- [ ] HomeDrawerVC에 onSearchBarTapped, onSettingsTapped 콜백 추가
- [ ] AppCoordinator 검색 플로우 변경 (full 전환 -> SearchVC 모달)
- [ ] AppCoordinator 검색 완료/취소 후 medium 복귀 로직 추가
- [ ] AppCoordinator detent 계산 변경
- [ ] DrawerContainerManager에 snapToDetent(completion:) 추가 (필요 시)
- [ ] 빌드 및 동작 확인
  - [ ] 홈드로어 헤더에 검색바/설정 표시
  - [ ] 검색바 탭 -> full 전환 -> SearchVC 모달
  - [ ] SearchVC 닫기 -> medium 복귀
  - [ ] 설정 버튼 동작
  - [ ] 지도 컨트롤 버튼 위치 정상
  - [ ] 드로어 pan gesture 정상 (헤더 드래그)
