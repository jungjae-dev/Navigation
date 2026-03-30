# Phase 2: 공통 UI 컴포넌트 생성

## 목표

Phase 1에서 정의한 디자인 토큰을 사용하는 재사용 가능한 공통 컴포넌트를 생성한다.
각 컴포넌트는 토큰만 참조하며, 매직넘버를 직접 사용하지 않는다.

## 작업 파일 (모두 신규 생성)

```
Common/UI/DesignSystem/
├── DrawerHeaderView.swift
├── DrawerSectionHeaderView.swift
├── DrawerListCell.swift
├── DrawerActionButton.swift
├── DrawerIconButton.swift
├── DrawerSeparator.swift
├── SearchBarView.swift
└── OverlayContainer.swift
```

---

## 2-1. DrawerHeaderView

모든 드로어 상단 고정 영역. 좌측/중앙/우측 슬롯 구조.

### 레이아웃

```
┌─────────────────────────────────────────────┐
│ [좌측영역]    [중앙 콘텐츠]    [우측 액션들]  │  44px
│  16px                              16px     │
└─────────────────────────────────────────────┘
```

### 인터페이스

```swift
final class DrawerHeaderView: UIView {

    // 슬롯 영역
    let leftArea: UIStackView       // 좌측 (아이콘 등)
    let centerView: UIView          // 중앙 (타이틀 or 검색바)
    let rightArea: UIStackView      // 우측 (액션 버튼들)
    let separator: DrawerSeparator  // 하단 구분선

    // 높이: Theme.Drawer.Header.height (44px)
    // 좌우 패딩: Theme.Drawer.Header.padding (16px)
    // rightArea 내부 간격: Theme.Spacing.xs (4px)

    // 편의 설정 메서드
    func setTitle(_ text: String)
    func setTitle(_ text: String, alignment: NSTextAlignment)
    func setCenterView(_ view: UIView)    // 커스텀 뷰 (검색바 등)
    func addRightAction(_ button: DrawerIconButton)
    func setLeftIcon(_ image: UIImage?, size: CGFloat)
}
```

### 사용 예시

```swift
// HomeDrawer: 검색바 + 설정
headerView.setCenterView(searchBarView)
headerView.addRightAction(settingsButton)

// SearchResult: 중앙 타이틀 + 닫기
headerView.setTitle("검색 결과", alignment: .center)
headerView.addRightAction(closeButton)

// POIDetail: 좌측 아이콘 + 타이틀 + 즐겨찾기 + 닫기
headerView.setLeftIcon(categoryIcon, size: 32)
headerView.setTitle(placeName)
headerView.addRightAction(favoriteButton)
headerView.addRightAction(closeButton)

// RoutePreview: 타이틀 + 즐겨찾기 + 닫기
headerView.setTitle(destinationName)
headerView.addRightAction(favoriteButton)
headerView.addRightAction(closeButton)
```

---

## 2-2. DrawerSectionHeaderView

섹션 구분 헤더. CollectionView/TableView 섹션 헤더로 사용.

### 레이아웃

```
┌─────────────────────────────────────────┐
│  [16×16 아이콘] [4px] 섹션 타이틀        │  36px
│  16px                                    │
└─────────────────────────────────────────┘
```

### 인터페이스

```swift
final class DrawerSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "DrawerSectionHeader"

    func configure(title: String, iconName: String?, iconColor: UIColor?)

    // 폰트: Theme.Drawer.SectionHeader.titleFont
    // 색상: Theme.Drawer.SectionHeader.titleColor
    // 아이콘: Theme.Drawer.SectionHeader.iconSize
    // 여백: Theme.Drawer.SectionHeader.horizontalPadding
}
```

### 기존 대체 대상

- `HomeSectionHeaderView` -> `DrawerSectionHeaderView`로 교체

---

## 2-3. DrawerListCell

범용 리스트 셀. UICollectionViewCell 기반.

### 레이아웃

```
┌─────────────────────────────────────────┐
│  ┌──────┐                               │
│  │ icon │ [12px] 제목              52px  │
│  │32×32 │        부제목                  │
│  └──────┘                               │
│  16px                          16px     │
├─────────────────────────────────────────┤  0.5px separator
```

### 인터페이스

```swift
final class DrawerListCell: UICollectionViewCell {

    static let reuseIdentifier = "DrawerListCell"

    func configure(
        title: String,
        subtitle: String?,
        iconImage: UIImage?,
        iconBackgroundColor: UIColor?,
        accessoryView: UIView?           // 체크마크, 시간 등
    )

    // 셀 높이: Theme.Drawer.Cell.height (52px)
    // 아이콘: Theme.Drawer.Cell.iconSize (32px)
    // 제목: Theme.Drawer.Cell.titleFont, titleColor
    // 부제목: Theme.Drawer.Cell.subtitleFont, subtitleColor
    // 간격: Theme.Drawer.Cell.iconToTextSpacing (12px)
    // 여백: Theme.Drawer.Cell.horizontalPadding (16px)
    // 구분선: DrawerSeparator (하단)

    var showsSeparator: Bool  // 마지막 셀은 구분선 숨김
}
```

### 기존 대체 대상

- `RecentSearchCell` -> `DrawerListCell`
- `SearchResultCell` -> `DrawerListCell`
- `RouteOptionCell` -> 커스텀 유지 (3열 정보), 토큰만 적용

---

## 2-4. DrawerActionButton

CTA 버튼. Primary / Secondary 스타일.

### 레이아웃

```
Primary:                          Secondary:
┌────────────────────────────┐   ┌────────────────────────────┐
│     [아이콘] 안내 시작      │   │       가상 주행             │
│     48px, primary filled   │   │     40px, border style     │
└────────────────────────────┘   └────────────────────────────┘
```

### 인터페이스

```swift
final class DrawerActionButton: UIButton {

    enum Style {
        case primary       // 48px, primary bg, white text
        case secondary     // 40px, secondaryBg, primary text, border
        case destructive   // 44px, destructive bg, white text
    }

    init(style: Style, title: String, iconName: String? = nil)

    var isLoading: Bool    // 로딩 인디케이터 표시

    // Primary:
    //   높이: Theme.Button.Primary.height (48px)
    //   폰트: Theme.Button.Primary.font
    //   배경: Theme.Button.Primary.backgroundColor
    //   전경: Theme.Button.Primary.foregroundColor
    //   모서리: Theme.Button.Primary.cornerRadius (12px)

    // Secondary:
    //   높이: Theme.Button.Secondary.height (40px)
    //   폰트: Theme.Button.Secondary.font
    //   배경: Theme.Button.Secondary.backgroundColor
    //   전경: Theme.Button.Secondary.foregroundColor
    //   테두리: Theme.Button.Secondary.borderColor, borderWidth (1px)
    //   모서리: Theme.Button.Secondary.cornerRadius (12px)
}
```

### 기존 대체 대상

- POIDetail 경로 버튼 -> `DrawerActionButton(.primary, "경로")`
- RoutePreview 안내시작 -> `DrawerActionButton(.primary, "안내 시작")`
- RoutePreview 가상주행 -> `DrawerActionButton(.secondary, "가상 주행")`
- Navigation 안내종료 -> `DrawerActionButton(.destructive, "안내 종료")`

---

## 2-5. DrawerIconButton

원형 아이콘 버튼. 닫기, 즐겨찾기, 설정 등에 사용.

### 레이아웃

```
┌──────┐
│  18  │  32×32 (최소 히트영역 44×44)
│  pt  │
└──────┘
```

### 인터페이스

```swift
final class DrawerIconButton: UIButton {

    enum Preset {
        case close          // xmark.circle.fill, secondaryLabel
        case favorite       // star / star.fill, primary
        case settings       // gearshape.fill, secondaryLabel
        case back           // chevron.left, label
    }

    init(preset: Preset)
    init(iconName: String, tintColor: UIColor)

    func setFavoriteState(_ isFavorite: Bool)

    // 크기: Theme.Button.Icon.size (32px)
    // 아이콘: Theme.Button.Icon.imageSize (18pt)
    // 히트영역: Theme.Button.Icon.hitAreaMinimum (44px)
}
```

### 기존 대체 대상

- 모든 드로어 닫기 버튼 -> `DrawerIconButton(.close)`
- RoutePreview 즐겨찾기 -> `DrawerIconButton(.favorite)`
- HomeVC 설정 버튼 -> `DrawerIconButton(.settings)`

---

## 2-6. DrawerSeparator

1px 구분선.

### 인터페이스

```swift
final class DrawerSeparator: UIView {

    enum Style {
        case fullWidth      // 전체 너비
        case inset          // 좌우 16px 여백
    }

    init(style: Style = .fullWidth)

    // 높이: 1 / UIScreen.main.scale (0.5px retina, 0.33px 3x)
    // 색상: Theme.Drawer.Separator.color
    // 인셋: Theme.Drawer.Separator.horizontalInset (16px)
}
```

---

## 2-7. SearchBarView

탭 가능한 검색바. HomeDrawer 헤더에서 사용.

### 레이아웃

```
┌─────────────────────────────────────┐
│  [🔍 20×20] [12px] 여기서 검색       │  40px
│  12px                       12px    │
└─────────────────────────────────────┘
  secondaryBackground, cornerRadius 12
```

### 인터페이스

```swift
final class SearchBarView: UIView {

    var onTapped: (() -> Void)?

    init(placeholder: String = "여기서 검색")

    // 높이: Theme.Drawer.SearchBar.height (40px)
    // 배경: Theme.Drawer.SearchBar.backgroundColor
    // 모서리: Theme.Drawer.SearchBar.cornerRadius (12px)
    // 아이콘: magnifyingglass, Theme.Drawer.SearchBar.iconSize (20px)
    // 텍스트: Theme.Drawer.SearchBar.font, placeholderColor
    // 내부여백: Theme.Drawer.SearchBar.horizontalPadding (12px)
}
```

### 기존 대체 대상

- HomeVC의 `searchBarContainer` (UIView + label + icon) -> `SearchBarView`

---

## 2-8. OverlayContainer

반투명 배경 컨테이너. 주행 배너, 재생 컨트롤에서 사용.

### 인터페이스

```swift
final class OverlayContainer: UIView {

    let contentView: UIView

    init(cornerRadius: CGFloat = Theme.Banner.cornerRadius)

    // 배경: Theme.Banner.backgroundColor (black 85%)
    // 모서리: 파라미터로 지정
    // clipsToBounds: true
}
```

### 기존 대체 대상

- NavigationVC 매뉴버 배너 배경
- PlaybackControlView 배경

---

## 체크리스트

- [ ] DrawerHeaderView 구현 (좌/중앙/우 슬롯 + separator)
- [ ] DrawerSectionHeaderView 구현 (UICollectionReusableView)
- [ ] DrawerListCell 구현 (UICollectionViewCell, 아이콘+제목+부제목)
- [ ] DrawerActionButton 구현 (primary/secondary/destructive)
- [ ] DrawerIconButton 구현 (close/favorite/settings/back preset)
- [ ] DrawerSeparator 구현 (fullWidth/inset)
- [ ] SearchBarView 구현 (탭 가능 검색바)
- [ ] OverlayContainer 구현 (반투명 배경)
- [ ] 빌드 확인 (컴포넌트만 생성, 아직 사용하는 코드 없음)
