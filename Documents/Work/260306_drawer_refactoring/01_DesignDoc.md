# Drawer Refactoring 설계서 - Modal Sheet -> Child VC (Stack 기반)

## 1. 배경 및 목표

### 1.1 현재 문제점

HomeDrawer를 `UISheetPresentationController` 기반 modal present로 구현한 구조에서 다음 문제가 발생:

1. **매 화면 전환마다 dismiss/re-present 반복** - 인스턴스를 매번 새로 생성
2. **push 전 반드시 dismiss 필수** - modal이 있으면 `navigationController.push` 불가
3. **중첩 sheet 타이밍 핵** - `asyncAfter(0.35)` 로 애니메이션 대기
4. **dismiss 함수 6개 난립** - 각각 미묘하게 다른 inset 복원 로직
5. **presenter 불일치** - `homeDrawer ?? navigationController` 조건 분기
6. **sheet delegate 모놀리식** - 하나의 delegate에서 모든 드로어 분기 처리

### 1.2 목표

- 드로어를 **child VC** 방식으로 전환하여 modal present 의존 제거
- dismiss/re-present 비용 제거 (hide/show로 대체)
- 타이밍 핵(`asyncAfter`) 제거
- push 제약 해소
- 드로어 상태 관리를 **스택 기반**으로 단순화
- 드로어 추가 시 확장이 용이한 구조

---

## 2. 아키텍처 - Stack 기반 단일 슬롯

### 2.1 개요

```
HomeViewController.view
|-- MapViewController (child, 전체 화면)
|-- 검색바 + 설정 버튼 (상단)
|
|-- [Drawer Stack] (하단, containerView 1개)
    |-- 드래그 핸들 (grabber)
    |-- Pan Gesture (detent 간 이동 전용)
    |-- Stack: [Home, SearchResult?, POIDetail?] (top만 표시)
```

### 2.2 스택 구조

| 항목 | 설명 |
|------|------|
| 스택 | `[DrawerEntry]` 배열, 항상 1개 이상 (root = Home) |
| 표시 | top 항목만 표시, 나머지는 `isHidden = true` |
| push | 새 drawer slide up + 기존 slide down (동시) |
| pop | top slide down + 이전 slide up (동시) |
| replaceStack | 스택 전체 교체 (RoutePreview 등) |

### 2.3 DrawerEntry

```swift
struct DrawerEntry {
    let viewController: UIViewController
    let detents: [DrawerDetent]
    var activeDetent: DrawerDetent
}
```

### 2.4 드로어 상태 전이

```
State A: Stack[Home]
State B: Stack[Home, SearchResult]
State C: Stack[Home, POI]
State D: Stack[Home, SearchResult, POI]
State E: Stack[RoutePreview]  (replaceStack)
State F: SearchVC fullscreen (드로어 숨김)
State G: Settings push (드로어 숨김)
State H: Navigation push (드로어 숨김)
State I: Virtual Drive push (드로어 숨김)
State J: GPX Playback push (드로어 숨김)
```

### 2.5 스택 연산 매핑

| 전환 | 연산 |
|------|------|
| A→B (검색 결과) | `pushDrawer(SearchResult)` |
| B→D (POI 선택) | `pushDrawer(POI)` |
| A→C (지도 POI 탭) | `pushDrawer(POI)` |
| D→B (POI 닫기) | `popDrawer()` |
| C→A (POI 닫기) | `popDrawer()` |
| B→A (SearchResult 닫기) | `restoreHomeDrawer()` → `replaceStack(Home)` |
| *→E (경로 탭) | `replaceStack(RoutePreview)` |
| E→A (RoutePreview 닫기) | `restoreHomeDrawer()` → `replaceStack(Home)` |
| *→F (검색바 탭) | `hideAll()` |
| *→G/H/I/J (push) | `hideAll()` or `clearAll()` |

---

## 3. 애니메이션 규칙

### 3.1 기본 규칙

| # | 규칙 | 설명 |
|---|------|------|
| 1 | push | 새 drawer slide up + 기존 slide down (동시, transform) |
| 2 | pop | top slide down + 이전 slide up (동시, transform) |
| 3 | replaceStack | 기존 top slide down + 새 drawer slide up (동시, transform) |
| 4 | 드래그 | detent 간 이동만, 최소 detent 아래로 불가 |
| 5 | 스와이프 dismiss | 미지원 (모든 드로어 동일 정책) |
| 6 | 전체 숨기기 (push) | container slide down |
| 7 | 전체 복원 (pop) | container slide up |

### 3.2 Push/Pop 애니메이션

```
시간 ─────────────────>
올라오는 것   ░░░@@████████  ↑ (transform → identity)
내려가는 것   ████████@@░░░  ↓ (identity → transform)
              ^^^ 동시 진행
```

- child view의 `transform`으로 독립 애니메이션
- 컨테이너 자체는 고정, child view만 이동
- completion에서 내려간 view는 `isHidden = true` (push) 또는 `removeFromParent` (pop)

### 3.3 닫기 정책

| 항목 | 정책 |
|------|------|
| 스와이프 dismiss | 제거 - 모든 드로어 공통 |
| 닫기(X) 버튼 | 유일한 닫기 수단 |
| 드래그 | detent 간 높이 조절 전용 (최소 detent 아래로 불가) |
| HomeDrawer 닫기 | 닫기 버튼 없음 (항상 표시) |

---

## 4. 전체 시나리오 전환 맵 (33개)

### 4.1 기본 전환

| # | 출발 | 액션 | 도착 | 스택 연산 |
|---|------|------|------|----------|
| 1 | 앱 시작 | start() | A | pushDrawer(Home) |
| 2 | A | 검색바 탭 | F | hideAll() |
| 3 | F | 검색 취소 | A | showTop() |
| 4 | F | 검색 결과 선택 | B | pushDrawer(SearchResult) |
| 5 | A | 지도 POI 탭 | C | pushDrawer(POI) |
| 6 | B | 결과 항목 탭 | D | pushDrawer(POI) |
| 7 | B | 닫기(X) | A | replaceStack(Home) |
| 9 | C | 경로 탭 | E | replaceStack(RoutePreview) |
| 10 | D | 경로 탭 | E | replaceStack(RoutePreview) |
| 11 | C | POI 닫기(X) | A | popDrawer() |
| 13 | D | POI 닫기(X) | B | popDrawer() |
| 15 | E | 닫기(X) | A | replaceStack(Home) |

### 4.2 설정/내비게이션 전환

| # | 출발 | 액션 | 도착 | 스택 연산 |
|---|------|------|------|----------|
| 17 | E | 안내 시작 | H | clearAll() → push NavigationVC |
| 18 | E | 가상 주행 | I | clearAll() → push NavigationVC |
| 19 | A | 즐겨찾기 탭 | E | replaceStack(RoutePreview) |
| 20 | A | 최근검색 탭 | E | replaceStack(RoutePreview) |
| 21 | A | 설정 버튼 | G | hideAll() → push SettingsVC |
| 22 | G | 뒤로가기 | A | pop → showTop() |
| 23 | H | 네비 종료 | A | pop → showTop() |
| 24 | I | 가상주행 종료 | A | pop → showTop() |
| 25 | J | GPX 종료 | A | pop → showTop() |
| 32 | E | GPX 재생 | J | clearAll() → push NavigationVC |

### 4.3 중첩 상태에서 검색 재진입

| # | 출발 | 액션 | 도착 | 스택 연산 |
|---|------|------|------|----------|
| 26 | B | 검색바 탭 | F | hideAll() |
| 27 | C | 검색바 탭 | F | hideAll() |
| 28 | D | 검색바 탭 | F | hideAll() |

### 4.4 기타

| # | 출발 | 액션 | 도착 | 스택 연산 |
|---|------|------|------|----------|
| 29 | B | 지도 annotation 탭 | D | pushDrawer(POI) |
| 30 | A | CarPlay 네비 시작 | H | clearAll() → push |
| 31 | B/C/D/E | CarPlay 네비 시작 | H | clearAll() → push |
| 33 | D | 지도 annotation 탭 | D | POI 내용만 update (스택 변경 없음) |

---

## 5. DrawerContainerManager 설계

### 5.1 인터페이스

```swift
final class DrawerContainerManager {

    // MARK: - Types
    struct DrawerEntry {
        let viewController: UIViewController
        let detents: [DrawerDetent]
        var activeDetent: DrawerDetent
    }

    // MARK: - Stack Operations
    func pushDrawer(_ vc: UIViewController, detents: [DrawerDetent], initialDetent: DrawerDetent, animated: Bool)
    func popDrawer(animated: Bool)
    func popToRoot(animated: Bool)
    func replaceStack(with vc: UIViewController, detents: [DrawerDetent], initialDetent: DrawerDetent, animated: Bool)

    // MARK: - Visibility
    func hideAll(animated: Bool)
    func showTop(animated: Bool)
    func clearAll(animated: Bool)    // removeAll VCs + hide

    // MARK: - Queries
    var stackDepth: Int { get }
    var topViewController: UIViewController? { get }
    func contains(_ vc: UIViewController) -> Bool

    // MARK: - Callback
    var onHeightChanged: ((CGFloat) -> Void)?
}
```

### 5.2 DrawerDetent

```swift
struct DrawerDetent: Equatable, Hashable {
    let identifier: String
    let heightResolver: (CGFloat) -> CGFloat

    static func absolute(_ height: CGFloat, id: String) -> DrawerDetent
    static func fractional(_ fraction: CGFloat, id: String) -> DrawerDetent
}
```

각 드로어별 detent 설정:

| 드로어 | Detent 구성 |
|--------|-----------|
| Home | small(200pt), medium(50%), large(100%) |
| SearchResult | small(200pt), medium(50%), large(100%) |
| POIDetail | poiDetail(320pt) 고정 |
| RoutePreview | compact(200pt), expanded(420pt) |

### 5.3 Pan Gesture + Detent Snap

```
드래그 방향: 위/아래
  - 현재 높이 기준으로 가장 가까운 detent로 snap
  - velocity > threshold: 다음/이전 detent로 점프
  - 최소 detent 아래로 드래그: rubber band 후 최소로 snap back
  - 최대 detent 위로 드래그: rubber band 후 최대로 snap back
  - spring animation (damping: 0.85, response: 0.3)
  - detent 변경 시 스택의 activeDetent도 업데이트
```

### 5.4 스크롤-디텐트 연동

내부 UIScrollView와 드로어 높이 변경을 연동:

| 조건 | 동작 |
|------|------|
| grabber 영역 터치 | 항상 드로어 드래그 |
| 스크롤 상단 + 아래로 드래그 | 드로어 축소 |
| 스크롤 하단 + 위로 드래그 | 드로어 확대 |
| 그 외 | 내부 스크롤 |

### 5.5 터치 패스쓰루

```swift
override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
}
```

---

## 6. 컴포넌트 구조 변경

### 6.1 Before (현재)

```
AppCoordinator
|-- navigationController.present(homeDrawer)        // modal sheet
|   |-- homeDrawer.present(searchResultDrawer)      // stacked sheet
|   |   |-- searchResultDrawer.present(poiDetail)   // stacked sheet
|   |-- homeDrawer.present(routePreviewDrawer)      // stacked sheet
|-- UISheetPresentationControllerDelegate (모놀리식)
|-- dismissHomeDrawer() / dismissAllDrawers() / ... (6개)
```

### 6.2 After (목표)

```
HomeViewController
|-- MapViewController (child)
|-- DrawerContainerManager
|   |-- containerView (DrawerContainerView)
|   |   |-- GrabberView
|   |   |-- contentView
|   |   |   |-- Stack: [HomeDrawerVC.view, SearchResultVC.view?, POIDetailVC.view?]
|   |   |   |   (top만 visible, 나머지 hidden)
|   |-- UIPanGestureRecognizer
|   |-- drawerStack: [DrawerEntry]

AppCoordinator
|-- drawerManager.pushDrawer(...)
|-- drawerManager.popDrawer()
|-- drawerManager.replaceStack(...)
|-- drawerManager.hideAll() / showTop() / clearAll()
```

### 6.3 AppCoordinator 변경 요약

| 제거 | 대체 |
|------|------|
| `presentHomeDrawer()` | `drawerManager.pushDrawer(homeVC, ...)` |
| `dismissHomeDrawer()` | `drawerManager.hideAll()` 또는 스택 연산 시 자동 |
| `dismissAllDrawers()` | `drawerManager.clearAll()` |
| `dismissIntermediateDrawers()` | 변수 정리 + `completion()` |
| `dismissSearchResultDrawerWithCleanup()` | `restoreHomeDrawer()` → `replaceStack(Home)` |
| `dismissPOIDetailWithCleanup()` | `drawerManager.popDrawer()` |
| `dismissRoutePreviewDrawerWithCleanup()` | `restoreHomeDrawer()` → `replaceStack(Home)` |
| `showOverlay()` / `hideOverlay()` | `pushDrawer()` / `popDrawer()` |
| `configureSheetDetents(for:)` | `DrawerDetent` 설정으로 대체 |
| `UISheetPresentationControllerDelegate` | `DrawerContainerManager.onHeightChanged` |
| `asyncAfter(0.35)` (2곳) | 제거 (child 교체라 대기 불필요) |

### 6.4 Map Inset 연동 단순화

```swift
drawerManager.onHeightChanged = { [weak self] height in
    self?.homeViewController.updateMapControlBottomOffset(height)
    self?.homeViewController.updateMapInsets(
        top: self?.mapTopInset ?? 0,
        bottom: height
    )
}
```

1곳에서 통합 관리.

---

## 7. 파일 변경 계획

### 7.1 신규 파일

| 파일 | 역할 |
|------|------|
| `DrawerContainerManager.swift` | 스택 기반 드로어 관리자 |
| `DrawerDetent.swift` | Detent 모델 |
| `DrawerContainerView.swift` | 터치 패스쓰루 + grabber 포함 컨테이너 뷰 |
| `GrabberView.swift` | 드래그 핸들 UI |

### 7.2 수정 파일

| 파일 | 변경 내용 |
|------|----------|
| `AppCoordinator.swift` | modal present → DrawerContainerManager 스택 호출로 전환 |
| `HomeViewController.swift` | DrawerContainerManager 초기화 + 소유 |
| `HomeDrawerViewController.swift` | `isModalInPresentation` 제거, sheet 관련 코드 제거 |
| `SearchResultDrawerViewController.swift` | sheet 관련 코드 제거 |
| `RoutePreviewDrawerViewController.swift` | sheet 관련 코드 제거 |
| `POIDetailViewController.swift` | sheet 관련 코드 제거 |

### 7.3 제거 대상

- `UISheetPresentationControllerDelegate` 전체 extension
- `asyncAfter(0.35)` 2곳
- dismiss 함수 6개
- `configureSheetDetents(for:)`
- `presentHomeDrawer()` 내 sheet 설정 코드
- `DrawerScrollHelper.swift` (삭제)
- Overlay 슬롯 관련 코드 전체 (`overlayContainerView`, `showOverlay`, `hideOverlay`)

---

## 8. 확장성

### 8.1 새 드로어 추가 시

```swift
// 새 드로어 표시
drawerManager.pushDrawer(
    newDrawerVC,
    detents: [.absolute(300, id: "new")],
    initialDetent: .absolute(300, id: "new")
)

// 닫기
drawerManager.popDrawer()
```

- 새 변수나 조건 분기 불필요
- `pushDrawer` / `popDrawer` 만으로 통일
- 복원 순서는 스택이 자동 관리

### 8.2 스택 깊이별 복원

```
Home → SearchResult → POI → NewDrawer
                              popDrawer() → POI 복원
                      popDrawer() → SearchResult 복원
              popDrawer() → Home 복원
```

---

## 9. 검증 방법

### 9.1 시나리오 테스트 (33개 전환)

4장의 전환 맵 기준으로 모든 시나리오를 수동 검증.

### 9.2 핵심 검증 항목

| # | 항목 | 기대 결과 |
|---|------|----------|
| 1 | 앱 시작 후 홈 드로어 | medium detent로 slide up 표시 |
| 2 | detent 드래그 (3단계) | 최소/중간/전체로 snap |
| 3 | 최소 detent 아래 드래그 | rubber band 후 snap back, dismiss 안 됨 |
| 4 | 드로어 뒤 지도 터치 | 정상 동작 (터치 패스쓰루) |
| 5 | 검색 → 결과 선택 | SearchResult push (asyncAfter 없이 즉시) |
| 6 | SearchResult 닫기 → Home | replaceStack 전환 |
| 7 | POI 닫기 | popDrawer → 이전 드로어 복원 |
| 8 | D→E (경로 탭) | replaceStack(RoutePreview) |
| 9 | 안내 시작 | clearAll() → NavigationVC push |
| 10 | 네비 종료 → Home | pop → showTop() |
| 11 | 설정 → 뒤로 | pop → showTop() |
| 12 | 지도 컨트롤 버튼 | detent 변경 시 위치 연동 |
| 13 | 지도 inset | detent 변경 시 map layoutMargins 연동 |
| 14 | CarPlay 네비 시작 | clearAll() → push |
| 15 | POI 닫기 후 SearchResult 스크롤/하이라이트 보존 | 스택에서 view hidden 유지로 상태 보존 |
| 16 | push/pop 동시 애니메이션 | 올라오는 것 ↑ + 내려가는 것 ↓ 동시 진행 |

### 9.3 빌드 검증

```bash
cd Navigation
xcodebuild build \
  -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet
```
