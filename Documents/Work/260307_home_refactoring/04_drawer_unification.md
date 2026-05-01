# Phase 4: 드로어 공통 컴포넌트 적용

## 목표

SearchResultDrawer, POIDetail, RoutePreview 드로어에 Phase 2에서 만든 공통 컴포넌트를 적용한다.
각 드로어의 개별 헤더/셀/버튼 구현을 공통 컴포넌트로 교체한다.

## 작업 파일

### 수정

- `Feature/Search/SearchResultDrawerViewController.swift`
- `Feature/Search/SearchResultCell.swift` (DrawerListCell로 대체 검토)
- `Feature/POIDetail/POIDetailViewController.swift`
- `Feature/RoutePreview/RoutePreviewDrawerViewController.swift`
- `Feature/RoutePreview/RouteOptionCell.swift` (토큰 적용)
- `Feature/Home/HomeDrawerViewController.swift` (섹션 헤더, 최근검색 셀 교체)
- `Feature/Home/RecentSearchCell.swift` (DrawerListCell로 대체 검토)
- `Feature/Home/HomeSectionHeaderView.swift` (DrawerSectionHeaderView로 대체 검토)

---

## 4-1. SearchResultDrawerViewController

### 변경 전

```
┌─────────────────────────────────────────┐
│              ── Grabber ──              │
├─────────────────────────────────────────┤
│          "검색 결과"          [✕ 18pt]  │  44px (커스텀 레이아웃)
│         (centerX/Y)    (trailing 16px)  │
│─────────────────────────────────────────│  1px separator (커스텀)
│  ┌─ TableView ────────────────────────┐ │
│  │  SearchResultCell (커스텀 셀)       │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 변경 후

```
┌─────────────────────────────────────────┐
│              ── Grabber ──              │
├─ DrawerHeaderView ─────────────────────┤
│          "검색 결과"      [✕ DrawerIcon]│  44px
├─────────────────────────────────────────┤  0.5px separator (내장)
│                                  8px   │
│  ┌─ TableView ────────────────────────┐ │
│  │  DrawerListCell                    │ │
│  │  DrawerListCell                    │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 코드 변경

```swift
// 삭제: titleLabel, closeButton, titleSeparator (개별 구현)
// 추가:
private let headerView = DrawerHeaderView()
private let closeButton = DrawerIconButton(preset: .close)

private func setupUI() {
    headerView.setTitle("검색 결과", alignment: .center)
    headerView.addRightAction(closeButton)

    // headerView constraints (top, leading, trailing)
    // tableView constraints (headerView.bottomAnchor + contentTopPadding)

    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
}
```

### 셀 교체 검토

- `SearchResultCell` -> `DrawerListCell`로 교체 가능
- configure: 장소 아이콘(카테고리별) + 장소명 + 주소
- highlight 상태: DrawerListCell에 `isHighlighted` 스타일 추가

---

## 4-2. POIDetailViewController

### 변경 전

```
┌─────────────────────────────────────────┐
│              ── Grabber ──              │
├─────────────────────────────────────────┤
│                                  [✕]   │  44px (닫기만)
├─── mainStack (top: 44px) ──────────────┤
│  [🏪 32×32]  장소명                     │  headerStack
│              주소                       │  infoStack
│  📞 전화 / 🌐 웹                        │  contactStack
│  [🔵 경로 48px]                         │  routeButton
└─────────────────────────────────────────┘
```

### 변경 후

```
┌─────────────────────────────────────────┐
│              ── Grabber ──              │
├─ DrawerHeaderView ─────────────────────┤
│  [🏪 32] 장소명       [☆ 32]  [✕ 32]  │  44px
├─────────────────────────────────────────┤  0.5px separator
│                                  8px   │
│  ┌─ contentStack (좌우 16px) ─────────┐ │
│  │  주소 (subheadline, secondaryLabel) │ │
│  │                        spacing: lg  │ │
│  │  📞 전화번호                        │ │
│  │  🌐 웹사이트                        │ │
│  │                        spacing: lg  │ │
│  │  [🔵 경로 DrawerActionButton 48px]  │ │
│  │                        padding: lg  │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 코드 변경

```swift
// 삭제: closeButton (개별 구현), categoryImageView/nameLabel (헤더로 이동)
// 추가:
private let headerView = DrawerHeaderView()
private let closeButton = DrawerIconButton(preset: .close)
private let favoriteButton = DrawerIconButton(preset: .favorite)  // 신규 추가
private let routeButton = DrawerActionButton(style: .primary, title: "경로", iconName: "arrow.triangle.turn.up.right.diamond.fill")

private func setupUI() {
    let categoryIcon = UIImage(systemName: iconName(for: place.category))
    headerView.setLeftIcon(categoryIcon, size: Theme.Drawer.Cell.iconSize)
    headerView.setTitle(place.name ?? "알 수 없는 장소")
    headerView.addRightAction(favoriteButton)
    headerView.addRightAction(closeButton)

    // contentStack: 주소 + 연락처 + 경로 버튼
    // headerView constraints
    // contentStack constraints (headerView.bottomAnchor + contentTopPadding)
}
```

### 신규 기능

- 즐겨찾기 버튼 추가 (기존에 POIDetail에는 없었음)
- onFavoriteTapped 콜백 추가 또는 ViewModel에서 처리

---

## 4-3. RoutePreviewDrawerViewController

### 변경 전

```
┌─────────────────────────────────────────┐
│              ── Grabber ──              │
├─────────────────────────────────────────┤
│  목적지명         [☆ 40×40]  [✕ 18pt] │  44px (커스텀)
│─────────────────────────────────────────│  0.5px (커스텀)
│  [자동차 | 도보] 32px                   │
│  ┌─ TableView 180px ─────────────────┐ │
│  │  RouteOptionCell                   │ │
│  └────────────────────────────────────┘ │
│  [가상주행 100px] [안내시작 fill] 48px   │
└─────────────────────────────────────────┘
```

### 변경 후

```
┌─────────────────────────────────────────┐
│              ── Grabber ──              │
├─ DrawerHeaderView ─────────────────────┤
│  목적지명              [☆ 32]  [✕ 32] │  44px
├─────────────────────────────────────────┤  0.5px separator (내장)
│                                  8px   │
│  ┌─ contentArea (좌우 16px) ──────────┐ │
│  │  [자동차 | 도보] 32px segment       │ │
│  │                        spacing: md  │ │
│  │  ┌─ TableView 180px ─────────────┐ │ │
│  │  │  RouteOptionCell (토큰 적용)   │ │ │
│  │  └────────────────────────────────┘ │ │
│  │                        spacing: md  │ │
│  │  [가상주행 secondary] [안내시작 primary] │
│  │                        padding: lg  │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 코드 변경

```swift
// 삭제: destinationLabel, favoriteButton, closeButton, titleSeparator (개별 구현)
// 추가:
private let headerView = DrawerHeaderView()
private let closeButton = DrawerIconButton(preset: .close)
private let favoriteButton = DrawerIconButton(preset: .favorite)
private let startButton = DrawerActionButton(style: .primary, title: "안내 시작")
private let virtualDriveButton = DrawerActionButton(style: .secondary, title: "가상 주행")

private func setupUI() {
    headerView.setTitle(viewModel.destinationName ?? "목적지")
    headerView.addRightAction(favoriteButton)
    headerView.addRightAction(closeButton)

    // segment: Theme.Segment 토큰 적용
    // 버튼: DrawerActionButton
    // headerView constraints
    // contentArea constraints (headerView.bottomAnchor + contentTopPadding)
}
```

### RouteOptionCell 토큰 적용

```swift
// RouteOptionCell 유지 (3열 구조가 DrawerListCell과 다름)
// 토큰만 적용:
//   아이콘: Theme.Drawer.Cell.iconSize 참조
//   시간 폰트: Theme.Drawer.Cell.titleFont
//   거리 폰트: Theme.Drawer.Cell.subtitleFont
//   색상: Theme.Drawer.Cell.titleColor, subtitleColor
//   여백: Theme.Drawer.Cell.horizontalPadding
```

---

## 4-4. HomeDrawerViewController 셀/헤더 교체

### 섹션 헤더 교체

```swift
// 변경 전: HomeSectionHeaderView (개별 구현)
// 변경 후: DrawerSectionHeaderView (공통)

collectionView.register(
    DrawerSectionHeaderView.self,
    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
    withReuseIdentifier: DrawerSectionHeaderView.reuseIdentifier
)

// viewForSupplementaryElementOfKind에서:
case .favorites:
    header.configure(title: "즐겨찾기", iconName: "star.fill", iconColor: Theme.Colors.primary)
case .recentSearches:
    header.configure(title: "최근 검색", iconName: "clock.arrow.circlepath", iconColor: Theme.Colors.primary)
```

### 최근검색 셀 교체

```swift
// 변경 전: RecentSearchCell (개별 구현, 아이콘 20×20)
// 변경 후: DrawerListCell (공통, 아이콘 32×32)

collectionView.register(
    DrawerListCell.self,
    forCellWithReuseIdentifier: DrawerListCell.reuseIdentifier
)

// cellForItemAt에서:
case .recentSearches:
    let cell = collectionView.dequeueReusableCell(...) as! DrawerListCell
    let history = viewModel.recentSearches.value[indexPath.item]
    let icon = UIImage(systemName: "clock.arrow.circlepath")
    cell.configure(title: history.placeName, subtitle: history.address, iconImage: icon)
    return cell
```

### 삭제 대상 파일 검토

- `HomeSectionHeaderView` (HomeDrawerViewController.swift 하단에 정의됨) -> 사용처 없으면 삭제
- `RecentSearchCell.swift` -> DrawerListCell로 완전 대체 시 삭제
- `SearchResultCell.swift` -> DrawerListCell로 완전 대체 시 삭제

---

## 체크리스트

- [ ] SearchResultDrawerVC: DrawerHeaderView + DrawerIconButton(.close) 적용
- [ ] SearchResultDrawerVC: SearchResultCell -> DrawerListCell 교체
- [ ] POIDetailVC: DrawerHeaderView (아이콘+장소명+즐겨찾기+닫기) 적용
- [ ] POIDetailVC: routeButton -> DrawerActionButton(.primary) 교체
- [ ] POIDetailVC: 즐겨찾기 기능 연동 (신규)
- [ ] RoutePreviewDrawerVC: DrawerHeaderView + DrawerIconButton 적용
- [ ] RoutePreviewDrawerVC: 버튼 -> DrawerActionButton 교체
- [ ] RoutePreviewDrawerVC: 세그먼트 -> Theme.Segment 토큰 적용
- [ ] RouteOptionCell: 토큰 적용
- [ ] HomeDrawerVC: HomeSectionHeaderView -> DrawerSectionHeaderView 교체
- [ ] HomeDrawerVC: RecentSearchCell -> DrawerListCell 교체
- [ ] 불필요한 개별 구현 코드/파일 삭제
- [ ] 빌드 및 동작 확인
  - [ ] 각 드로어 헤더 표시 정상
  - [ ] 닫기/즐겨찾기 버튼 동작
  - [ ] 셀 탭/선택 동작
  - [ ] 하이라이트 상태 (SearchResult)
  - [ ] pan gesture 충돌 없음
