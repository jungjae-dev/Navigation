# 홈 화면 지도 컨트롤 버튼 — 개발 계획서

## 1. 개요

### 배경
홈 화면 지도에 직접 제어할 수 있는 버튼이 없어 사용자가 현위치 이동, 방향 초기화, 지도 유형 전환 등의 작업을 수행할 수 없다. 지도 앱의 기본 기능으로서 **현위치, 정북방향, 지도 모드** 3개의 컨트롤 버튼을 추가한다.

### 목표
- 홈 화면 지도 우측에 **3개 컨트롤 버튼** 배치
- 현위치 버튼: `MKUserTrackingMode` 3단계 순환 (none → follow → followWithHeading)
- 정북방향 버튼: 지도 heading을 0°(북쪽)로 리셋
- 지도 모드 버튼: `.standard` → `.satellite` → `.hybrid` 3종 순환
- 드로어 높이에 따라 버튼 위치가 연동 (small/medium만 추적, large에서는 clamp)

### 관련 문서
- [HomeDrawer.md](./HomeDrawer.md) — 드로어 구조, DrawerDetent 설계
- [Architecture.md](../Architecture.md) — 프로젝트 아키텍처
- [TechSpec.md](../TechSpec.md) — 기술 명세

---

## 2. 현재 구현 vs 목표 비교

### 현재 구현 (Before)

```
┌─────────────────────────────┐
│  🔍 여기서 검색       ⚙️     │  ← 검색바 + 설정 버튼
├─────────────────────────────┤
│                             │
│                             │
│                             │
│         [ 지 도 ]           │  ← 지도 컨트롤 버튼 없음
│           📍                │     시스템 나침반만 우측 상단
│                             │
│                             │
├─────────────────────────────┤  ← 드로어 (200pt)
│  ── handle ──               │
│  ⭐ 즐겨찾기 / 🕐 최근 검색   │
└─────────────────────────────┘
```

**문제점:**
- 현위치로 돌아가는 버튼 없음 → 지도를 패닝한 후 복귀 불가
- 지도 회전 후 북쪽으로 리셋할 수 없음 (시스템 나침반이 있으나 커스텀 디자인 불가)
- 위성 지도 전환 불가

### 목표 구현 (After)

```
┌─────────────────────────────┐
│  🔍 여기서 검색       ⚙️     │  ← 검색바 + 설정 버튼
├─────────────────────────┬───┤
│                         │ ◎ │  ← 현위치 버튼 (location)
│                         ├───┤
│                         │ ◉ │  ← 정북방향 버튼 (location.north.fill)
│         [ 지 도 ]       ├───┤
│           📍            │ ▢ │  ← 지도 모드 버튼 (map)
│                         └───┘
│                             │
├─────────────────────────────┤  ← 드로어 (200pt)
│  ── handle ──               │
│  ⭐ 즐겨찾기 / 🕐 최근 검색   │
└─────────────────────────────┘
```

**개선사항:**
- 48×48pt 원형 버튼 3개를 세로 스택으로 배치
- 기존 `settingsButton`과 동일한 시각적 스타일 (일관성)
- 드로어 높이에 따라 버튼 위치가 자연스럽게 연동
- MKMapView 내장 나침반을 숨기고 커스텀 정북 버튼으로 대체

---

## 3. 레이아웃 상세

### 3.1 버튼 배치 및 치수

```
                              ┌─ trailing: 16pt (Theme.Spacing.lg) ─┐
                              │                                      │
                              │  ┌──────────┐                        │
                              │  │ 현위치    │  48 × 48pt             │
                              │  │ location │  cornerRadius: 24      │
                              │  └──────────┘                        │
                              │       │ spacing: 8pt (Theme.Spacing.sm)
                              │  ┌──────────┐                        │
                              │  │ 정북방향   │  48 × 48pt             │
                              │  │ north    │  cornerRadius: 24      │
                              │  └──────────┘                        │
                              │       │ spacing: 8pt                  │
                              │  ┌──────────┐                        │
                              │  │ 지도모드   │  48 × 48pt             │
                              │  │ map      │  cornerRadius: 24      │
                              │  └──────────┘                        │
                              │       │ padding: 12pt (Theme.Spacing.md)
                              │  ─────┴──────────── 드로어 상단 ──────│
```

**스택 전체 크기:**
- 너비: 48pt
- 높이: 48 + 8 + 48 + 8 + 48 = **160pt**
- 우측 여백: 16pt (settingsButton과 동일)
- 드로어 상단과 간격: 12pt

### 3.2 버튼 스타일 (settingsButton과 동일)

```swift
// 모든 버튼 공통 스타일
backgroundColor = Theme.Colors.secondaryBackground
tintColor       = Theme.Colors.secondaryLabel
cornerRadius    = 24  // 48pt / 2 (원형)
shadowColor     = Theme.Shadow.color     // .black
shadowOpacity   = Theme.Shadow.opacity   // 0.15
shadowOffset    = Theme.Shadow.offset    // (0, 2)
shadowRadius    = Theme.Shadow.radius    // 8
iconConfig      = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
```

### 3.3 Z-Order (뷰 계층 순서)

```
HomeViewController.view
│
├── [0] MapViewController.view     ← 전체 화면 지도 (맨 아래)
├── [1] settingsButton             ← 상단 우측
├── [2] searchBarContainer         ← 상단 좌측
├── [3] MapControlButtonsView      ← 우측 중앙 (드로어 위, 지도 위)
└── [4] HomeDrawerVC.view          ← 하단 드로어 (맨 위)
```

> **핵심**: `setupMapControlButtons()`를 `setupDrawer()` 전에 호출하여 드로어가 버튼 위에 오도록 함

---

## 4. 드로어 연동 — 버튼 위치 추적

### 4.1 동작 규칙

```
드로어 높이        │ 버튼 위치                         │ 비고
──────────────────┼───────────────────────────────────┼────────────────
small  (200pt)    │ bottom = -(200 + 12)pt            │ 드로어 바로 위
medium (50%)      │ bottom = -(50% + 12)pt            │ 드로어 따라 올라감
large  (최대)     │ bottom = -(50% + 12)pt (clamp)    │ medium 위치에서 멈춤
팬 드래그 중       │ min(currentHeight, mediumHeight)   │ 실시간 추적 + clamp
```

### 4.2 위치 추적 다이어그램

```
[small]              [medium]             [large]
┌───────────┐      ┌───────────┐      ┌───────────┐
│ 🔍    ⚙️   │      │ 🔍    ⚙️   │      │ 🔍    ⚙️   │
│           │      │           │      │           │
│       ┌─┐ │      │           │      │       ┌─┐ │  ← medium 위치에서
│       │◎│ │      │       ┌─┐ │      │       │◎│ │     clamp (더 이상
│       │◉│ │      │       │◎│ │      │       │◉│ │     올라가지 않음)
│       │▢│ │      │       │◉│ │      │       │▢│ │
│       └─┘ │      │       │▢│ │      ├───────────┤
│    12pt ↕ │      │       └─┘ │      │ ── grab ──│
├───────────┤      │    12pt ↕ │      │ ⭐ 즐겨찾기 │
│ ── grab ──│      ├───────────┤      │ 🕐 최근검색 │
│ ⭐ 즐겨... │      │ ── grab ──│      │ ...       │
└───────────┘      │ ⭐ 즐겨찾기 │      └───────────┘
                   │ 🕐 최근검색 │
                   └───────────┘
```

### 4.3 통신 방식 — 드로어 → 홈VC

현재 `HomeDrawerViewController`는 detent 변경을 부모에게 통지하지 않는다. 2개의 콜백을 추가한다:

```
HomeDrawerViewController                    HomeViewController
┌─────────────────────────┐                ┌─────────────────────┐
│                         │                │                     │
│ handlePan(.changed)     │ ──onHeight──→  │ updateMapControl    │
│   heightConstraint 변경  │   Changed      │   PositionDuringPan │
│                         │                │   (height: CGFloat) │
│                         │                │                     │
│ snapToDetent(:)         │ ──onDetent──→  │ updateMapControl    │
│   currentDetent 변경     │   Changed      │   Position          │
│                         │                │   (for: DrawerDetent)│
└─────────────────────────┘                └─────────────────────┘
```

```swift
// HomeDrawerViewController에 추가
var onDetentChanged: ((DrawerDetent) -> Void)?    // snap 완료 시
var onHeightChanged: ((CGFloat) -> Void)?          // 팬 드래그 실시간
```

### 4.4 위치 계산 로직

```swift
// 팬 드래그 중 (실시간)
func updateMapControlPositionDuringPan(height: CGFloat) {
    let mediumHeight = DrawerDetent.medium.height(in: view)
    let effectiveHeight = min(height, mediumHeight)  // ← clamp
    mapControlBottomConstraint.constant = -(effectiveHeight + 12)
}

// snap 완료 시 (애니메이션)
func updateMapControlPosition(for detent: DrawerDetent) {
    let drawerHeight: CGFloat
    switch detent {
    case .small, .medium:
        drawerHeight = detent.height(in: view)
    case .large:
        drawerHeight = DrawerDetent.medium.height(in: view)  // ← clamp
    }
    // 스프링 애니메이션 (드로어와 동일 파라미터)
    // duration: 0.35, damping: 0.8, velocity: 0.5
    mapControlBottomConstraint.constant = -(drawerHeight + 12)
}
```

---

## 5. 버튼 동작 상세

### 5.1 현위치 버튼 — MKUserTrackingMode 순환

```
┌──────────────────┐     탭     ┌──────────────────┐     탭     ┌──────────────────┐
│   .none          │ ─────────→ │   .follow        │ ─────────→ │ .followWithHeading│
│   ○ location     │            │   ● location.fill│            │ ● north.line.fill │
│   gray tint      │            │   blue tint      │            │ blue tint         │
└──────────────────┘            └──────────────────┘            └──────────────────┘
         ▲                                                              │
         │                            탭                                │
         └──────────────────────────────────────────────────────────────┘
```

**지도 직접 조작 시 자동 리셋:**
```
사용자가 지도를 팬/줌 → MKMapView가 자동으로 .none으로 리셋
                       → mapView(_:didChange mode:) 델리게이트 호출
                       → onTrackingModeChanged 콜백 → 아이콘 업데이트
```

### 5.2 정북방향 버튼 — Heading 리셋

```
[회전된 상태]              탭              [정북 상태]
┌───────────┐          ─────────→        ┌───────────┐
│     ↗     │   camera.heading = 0°     │     ↑     │
│    지도    │    animated: true         │    지도    │
│   (45°)   │                           │   (0°)    │
└───────────┘                           └───────────┘
```

### 5.3 지도 모드 버튼 — 3종 순환

```
┌──────────────┐     탭     ┌──────────────┐     탭     ┌──────────────┐
│  .standard   │ ─────────→ │  .satellite  │ ─────────→ │   .hybrid    │
│  ▢ map       │            │  ● globe     │            │  ▣ map.fill  │
└──────────────┘            └──────────────┘            └──────────────┘
        ▲                                                       │
        │                         탭                             │
        └───────────────────────────────────────────────────────┘
```

---

## 6. 아이콘 상태표

### 6.1 현위치 버튼

| 상태 | SF Symbol | Tint Color | 설명 |
|------|-----------|------------|------|
| `.none` | `location` | `secondaryLabel` (gray) | 추적 안 함 |
| `.follow` | `location.fill` | `primary` (systemBlue) | 현위치 추적 |
| `.followWithHeading` | `location.north.line.fill` | `primary` (systemBlue) | 방향 추적 |

### 6.2 정북방향 버튼

| 상태 | SF Symbol | Tint Color | 설명 |
|------|-----------|------------|------|
| 항상 | `location.north.fill` | `secondaryLabel` (gray) | 탭하면 heading → 0° |

### 6.3 지도 모드 버튼

| 상태 | SF Symbol | Tint Color | 설명 |
|------|-----------|------------|------|
| `.standard` | `map` | `secondaryLabel` (gray) | 일반 지도 |
| `.satellite` | `globe.americas.fill` | `secondaryLabel` (gray) | 위성 지도 |
| `.hybrid` | `map.fill` | `secondaryLabel` (gray) | 하이브리드 |

---

## 7. 아키텍처

### 7.1 컴포넌트 구조

```
┌────────────────────────────────────────────────────────────┐
│                     HomeViewController                       │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  MapViewController (child VC, index: 0)                 │  │
│  │  - MKMapView (전체 화면)                                 │  │
│  │  - showsCompass = false (커스텀 버튼으로 대체)             │  │
│  │  + cycleUserTrackingMode() → MKUserTrackingMode         │  │
│  │  + resetHeadingToNorth()                                │  │
│  │  + cycleMapType() → MKMapType                           │  │
│  │  + onTrackingModeChanged: ((MKUserTrackingMode) -> Void)│  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  검색 바 + 설정 버튼 (subview, 상단 고정)                  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────┐                                    │
│  │ MapControlButtonsView│ ← 🆕 신규                          │
│  │ (UIView, 우측 배치)    │                                    │
│  │ ┌──────────────────┐ │                                    │
│  │ │ UIStackView      │ │                                    │
│  │ │ (vertical, 8pt)  │ │                                    │
│  │ │ ┌──────────────┐ │ │                                    │
│  │ │ │ 현위치 버튼    │ │ │                                    │
│  │ │ ├──────────────┤ │ │                                    │
│  │ │ │ 정북방향 버튼  │ │ │                                    │
│  │ │ ├──────────────┤ │ │                                    │
│  │ │ │ 지도모드 버튼  │ │ │                                    │
│  │ │ └──────────────┘ │ │                                    │
│  │ └──────────────────┘ │                                    │
│  └──────────────────────┘                                    │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  HomeDrawerViewController (child VC, 하단)               │  │
│  │  + onDetentChanged: ((DrawerDetent) -> Void)?           │  │  ← 🆕 추가
│  │  + onHeightChanged: ((CGFloat) -> Void)?                │  │  ← 🆕 추가
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### 7.2 이벤트 흐름

```
[버튼 탭 이벤트]

MapControlButtonsView                HomeViewController           MapViewController
┌──────────────────┐               ┌──────────────────┐         ┌──────────────────┐
│                  │               │                  │         │                  │
│ onCurrentLocation│──callback──→  │ handleCurrent    │──call─→ │ cycleUserTracking│
│ Tapped           │               │ LocationTapped() │         │ Mode()           │
│                  │               │                  │ ←return │ → MKUserTracking │
│                  │               │ updateIcon()     │ newMode │   Mode           │
│                  │               │                  │         │                  │
│ onNorthDirection │──callback──→  │ handleNorth      │──call─→ │ resetHeadingTo   │
│ Tapped           │               │ DirectionTapped()│         │ North()          │
│                  │               │                  │         │                  │
│ onMapMode        │──callback──→  │ handleMapMode    │──call─→ │ cycleMapType()   │
│ Tapped           │               │ Tapped()         │         │ → MKMapType      │
│                  │               │ updateIcon()     │ ←return │                  │
└──────────────────┘               └──────────────────┘         └──────────────────┘
```

```
[트래킹 모드 자동 리셋]

MKMapView                      MapViewController            HomeViewController
┌──────────────┐              ┌──────────────────┐         ┌──────────────────┐
│ 사용자가      │              │                  │         │                  │
│ 지도를 팬     │──delegate──→ │ mapView(_:did    │         │                  │
│              │              │ Change mode:)    │──call──→│ onTrackingMode   │
│              │              │                  │         │ Changed          │
│              │              │                  │         │ → updateIcon()   │
└──────────────┘              └──────────────────┘         └──────────────────┘
```

---

## 8. 구현 상세

### 8.1 변경 파일 요약

```
Navigation/Navigation/
├── Feature/Home/
│   ├── MapControlButtonsView.swift      ← 🆕 신규 생성
│   │   - UIStackView (vertical) + 버튼 3개
│   │   - 콜백: onCurrentLocationTapped, onNorthDirectionTapped, onMapModeTapped
│   │   - 상태 업데이트: updateCurrentLocationIcon(), updateMapModeIcon()
│   │
│   ├── HomeViewController.swift         ← ✏️ 수정
│   │   - mapControlButtons 프로퍼티 추가
│   │   - mapControlBottomConstraint 프로퍼티 추가
│   │   - setupMapControlButtons() 메서드 추가
│   │   - viewDidLoad()에 setupMapControlButtons() 호출 추가
│   │   - 드로어 콜백 연결 (onDetentChanged, onHeightChanged)
│   │   - 버튼 액션 핸들러 3개 추가
│   │   - mapViewController.onTrackingModeChanged 연결
│   │
│   ├── HomeDrawerViewController.swift   ← ✏️ 수정
│   │   - onDetentChanged 콜백 프로퍼티 추가
│   │   - onHeightChanged 콜백 프로퍼티 추가
│   │   - handlePan(.changed)에서 onHeightChanged 호출
│   │   - snapToDetent()에서 onDetentChanged 호출
│   │
│   ├── HomeViewModel.swift              ← 변경 없음
│   ├── FavoriteCell.swift               ← 변경 없음
│   └── RecentSearchCell.swift           ← 변경 없음
│
├── Map/
│   └── MapViewController.swift          ← ✏️ 수정
│       - showsCompass = false (setupMapView, configureForStandard)
│       - cycleUserTrackingMode() 메서드 추가
│       - resetHeadingToNorth() 메서드 추가
│       - cycleMapType() 메서드 추가
│       - onTrackingModeChanged 콜백 프로퍼티 추가
│       - mapView(_:didChange mode:) 델리게이트 추가
│
└── Coordinator/
    └── AppCoordinator.swift             ← 변경 없음
```

### 8.2 신규 파일: `MapControlButtonsView.swift`

**위치**: `Navigation/Navigation/Feature/Home/MapControlButtonsView.swift`

**구조:**

```swift
final class MapControlButtonsView: UIView {

    // MARK: - Callbacks
    var onCurrentLocationTapped: (() -> Void)?
    var onNorthDirectionTapped: (() -> Void)?
    var onMapModeTapped: (() -> Void)?

    // MARK: - UI
    private let stackView: UIStackView          // vertical, spacing: 8pt
    private let currentLocationButton: UIButton  // 48×48, location icon
    private let northDirectionButton: UIButton   // 48×48, location.north.fill icon
    private let mapModeButton: UIButton          // 48×48, map icon

    // MARK: - Setup
    private func setupUI()           // 스택뷰 + 버튼 제약조건
    private func setupActions()      // addTarget for 3 buttons
    private func setupAccessibility() // 접근성 레이블

    // MARK: - State Updates
    func updateCurrentLocationIcon(for: MKUserTrackingMode)  // 아이콘 + 색상 변경
    func updateMapModeIcon(for: MKMapType)                    // 아이콘 변경
}
```

### 8.3 수정 파일: `HomeDrawerViewController.swift`

**추가할 코드:**

```swift
// 콜백 프로퍼티 (line 65~66 근처)
var onDetentChanged: ((DrawerDetent) -> Void)?
var onHeightChanged: ((CGFloat) -> Void)?

// handlePan .changed case (line 146 이후)
onHeightChanged?(heightConstraint.constant)

// snapToDetent (line 193 이후)
onDetentChanged?(detent)
```

### 8.4 수정 파일: `MapViewController.swift`

**변경할 코드:**

```swift
// setupMapView() — 나침반 숨김
mapView.showsCompass = false    // true → false

// configureForStandard() — 나침반 숨김 유지
mapView.showsCompass = false    // true → false
```

**추가할 코드:**

```swift
// MARK: - Public: Map Controls

var onTrackingModeChanged: ((MKUserTrackingMode) -> Void)?

func cycleUserTrackingMode() -> MKUserTrackingMode {
    // .none → .follow → .followWithHeading → .none
    let next: MKUserTrackingMode = switch mapView.userTrackingMode {
    case .none: .follow
    case .follow: .followWithHeading
    case .followWithHeading: .none
    @unknown default: .none
    }
    mapView.setUserTrackingMode(next, animated: true)
    return next
}

func resetHeadingToNorth() {
    let camera = mapView.camera
    camera.heading = 0
    mapView.setCamera(camera, animated: true)
}

func cycleMapType() -> MKMapType {
    // .standard → .satellite → .hybrid → .standard
    let next: MKMapType = switch mapView.mapType {
    case .standard: .satellite
    case .satellite: .hybrid
    case .hybrid: .standard
    default: .standard
    }
    mapView.mapType = next
    return next
}

// MKMapViewDelegate (기존 extension에 추가)
func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
    onTrackingModeChanged?(mode)
}
```

### 8.5 수정 파일: `HomeViewController.swift`

**추가할 프로퍼티:**

```swift
private let mapControlButtons = MapControlButtonsView()
private var mapControlBottomConstraint: NSLayoutConstraint!
```

**viewDidLoad 수정:**

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupMapChild()
    setupSearchBar()
    setupSettingsButton()
    setupMapControlButtons()   // ← 추가 (setupDrawer 전 = z-order 아래)
    setupDrawer()
    setupAccessibility()
    bindViewModel()
    handleInitialPermission()
}
```

**추가 메서드:**

```swift
// MARK: - Map Control Buttons

private func setupMapControlButtons() {
    view.addSubview(mapControlButtons)

    mapControlBottomConstraint = mapControlButtons.bottomAnchor.constraint(
        equalTo: view.bottomAnchor,
        constant: -(200 + Theme.Spacing.md)  // 초기: small detent + padding
    )

    NSLayoutConstraint.activate([
        mapControlButtons.trailingAnchor.constraint(
            equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg
        ),
        mapControlBottomConstraint,
    ])

    // 버튼 액션 연결
    mapControlButtons.onCurrentLocationTapped = { [weak self] in
        self?.handleCurrentLocationTapped()
    }
    mapControlButtons.onNorthDirectionTapped = { [weak self] in
        self?.handleNorthDirectionTapped()
    }
    mapControlButtons.onMapModeTapped = { [weak self] in
        self?.handleMapModeTapped()
    }

    // 트래킹 모드 자동 리셋 감지
    mapViewController.onTrackingModeChanged = { [weak self] mode in
        self?.mapControlButtons.updateCurrentLocationIcon(for: mode)
    }
}

// MARK: - Map Control Actions

private func handleCurrentLocationTapped() {
    let newMode = mapViewController.cycleUserTrackingMode()
    mapControlButtons.updateCurrentLocationIcon(for: newMode)
}

private func handleNorthDirectionTapped() {
    mapViewController.resetHeadingToNorth()
}

private func handleMapModeTapped() {
    let newMapType = mapViewController.cycleMapType()
    mapControlButtons.updateMapModeIcon(for: newMapType)
}

// MARK: - Drawer Position Tracking

private func updateMapControlPosition(for detent: HomeDrawerViewController.DrawerDetent) {
    let drawerHeight: CGFloat = switch detent {
    case .small, .medium:
        detent.height(in: view)
    case .large:
        HomeDrawerViewController.DrawerDetent.medium.height(in: view)  // clamp
    }

    UIView.animate(
        withDuration: 0.35, delay: 0,
        usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5,
        options: .curveEaseInOut
    ) {
        self.mapControlBottomConstraint.constant = -(drawerHeight + Theme.Spacing.md)
        self.view.layoutIfNeeded()
    }
}

private func updateMapControlPositionDuringPan(height: CGFloat) {
    let mediumHeight = HomeDrawerViewController.DrawerDetent.medium.height(in: view)
    let effectiveHeight = min(height, mediumHeight)  // clamp at medium
    mapControlBottomConstraint.constant = -(effectiveHeight + Theme.Spacing.md)
}
```

**setupDrawer()에 콜백 추가:**

```swift
private func setupDrawer() {
    // ... 기존 코드 ...
    drawer.didMove(toParent: self)

    // 드로어 위치 추적 콜백 (추가)
    drawer.onDetentChanged = { [weak self] detent in
        self?.updateMapControlPosition(for: detent)
    }
    drawer.onHeightChanged = { [weak self] height in
        self?.updateMapControlPositionDuringPan(height: height)
    }
}
```

---

## 9. 엣지 케이스

### 9.1 지도 팬 시 트래킹 모드 리셋

```
사용자가 현위치 버튼 탭 (→ .follow)
    ▼
사용자가 지도를 직접 패닝
    ▼
MKMapView가 자동으로 .none으로 리셋
    ▼
mapView(_:didChange mode:) 호출
    ▼
onTrackingModeChanged 콜백
    ▼
아이콘이 "location" (gray)으로 복귀
```

### 9.2 네비게이션 모드에서 버튼 숨김

```
HomeVC → push → RoutePreviewVC → push → NavigationVC
                                         │
                                         ▼
                                   MapVC가 NavigationVC로
                                   reparent됨
                                         │
                                         ▼
                                   HomeVC가 nav stack에서
                                   가려짐 → 버튼 자연히 숨김
                                         │
                                         ▼ (네비 종료, pop)
                                   HomeVC 다시 보임
                                   → 버튼도 함께 복귀
```

> **별도 숨김 로직 불필요** — 버튼은 HomeVC의 subview이므로 HomeVC가 가려지면 같이 가려짐

### 9.3 위치 권한 미허용 시

```
위치 권한 = denied
    ▼
현위치 버튼 탭 → cycleUserTrackingMode()
    ▼
mapView.setUserTrackingMode(.follow, animated: true)
    ▼
MKMapView가 권한 요청 alert을 자동 표시 (시스템 동작)
```

### 9.4 화면 회전 / Safe Area 변경

- `medium` 높이 = `view.bounds.height * 0.5` → 회전 시 변경됨
- 드로어가 `viewDidLayoutSubviews()`에서 재계산 → `onDetentChanged` 호출
- 버튼 위치도 자동으로 업데이트

---

## 10. 접근성

```swift
// 현위치 버튼
accessibilityLabel = "현재 위치"
accessibilityHint = "현재 위치로 이동합니다"

// 정북방향 버튼
accessibilityLabel = "북쪽 방향"
accessibilityHint = "지도를 북쪽으로 정렬합니다"

// 지도모드 버튼
accessibilityLabel = "지도 모드"
accessibilityHint = "지도 표시 유형을 변경합니다"
```

---

## 11. 검증 방법

### 11.1 기능 테스트

| # | 테스트 항목 | 예상 결과 |
|---|-----------|----------|
| 1 | 앱 실행 후 홈 화면 | 우측에 3개 버튼 표시, 드로어 위에 위치 |
| 2 | 현위치 버튼 탭 1회 | 현위치로 이동, 아이콘 → `location.fill` (blue) |
| 3 | 현위치 버튼 탭 2회 | 방향 추적 모드, 아이콘 → `location.north.line.fill` |
| 4 | 현위치 버튼 탭 3회 | 추적 해제, 아이콘 → `location` (gray) |
| 5 | 추적 중 지도 패닝 | 추적 자동 해제, 아이콘 → `location` (gray) |
| 6 | 정북방향 버튼 탭 | 지도 heading → 0° (북쪽 위), 애니메이션 |
| 7 | 지도모드 버튼 탭 1회 | 위성 지도, 아이콘 → `globe.americas.fill` |
| 8 | 지도모드 버튼 탭 2회 | 하이브리드, 아이콘 → `map.fill` |
| 9 | 지도모드 버튼 탭 3회 | 일반 지도 복귀, 아이콘 → `map` |

### 11.2 드로어 연동 테스트

| # | 테스트 항목 | 예상 결과 |
|---|-----------|----------|
| 1 | 드로어 최소 → 중간 드래그 | 버튼이 드로어를 따라 위로 이동 |
| 2 | 드로어 중간 → 전체 드래그 | 버튼이 중간 위치에서 멈춤 (clamp) |
| 3 | 드로어 전체 → 최소 드래그 | 버튼이 다시 최소 위치로 내려옴 |
| 4 | 드로어 빠른 스와이프 | 버튼이 스프링 애니메이션으로 스냅 |
| 5 | 드로어 드래그 중 (실시간) | 버튼이 부드럽게 드로어를 따라감 |

### 11.3 화면 전환 테스트

| # | 시나리오 | 예상 결과 |
|---|---------|----------|
| 1 | 검색 → 취소 → 홈 | 버튼 상태 유지, 위치 유지 |
| 2 | 경로 미리보기 → 뒤로 | 버튼 상태 유지 |
| 3 | 네비게이션 시작 → 종료 | 버튼 다시 표시, 기본 상태 |

### 11.4 빌드 검증

```bash
xcodebuild build \
  -project Navigation.xcodeproj \
  -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet
```
