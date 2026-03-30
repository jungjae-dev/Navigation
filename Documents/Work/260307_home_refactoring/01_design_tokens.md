# Phase 1: 디자인 시스템 토큰 정의

## 목표

기존 `Theme`의 기본 토큰(Colors, Fonts, Spacing 등)을 기반으로, 각 화면/컴포넌트에서 사용하는 시맨틱 토큰을 정의한다.
하드코딩된 매직넘버를 의미 있는 이름의 토큰으로 교체하여 일관성과 유지보수성을 확보한다.

## 작업 파일

### 신규 생성

- `Common/UI/DesignSystem/Theme+Drawer.swift`
- `Common/UI/DesignSystem/Theme+Component.swift`

### 수정

- `Common/UI/Theme.swift` (기본 토큰 보완)

---

## 1-1. 기존 Theme 보완 (Theme.swift)

### 현재 상태

```swift
enum Theme {
    enum Colors { ... }     // 8개 색상
    enum Fonts { ... }      // 8 + 3 내비 전용
    enum Spacing { ... }    // 7단계 (xxs~xxl)
    enum CornerRadius { ... } // 4단계
    enum Shadow { ... }     // 단일 스타일
}
```

### 추가할 기본 토큰

```swift
// Theme.swift에 추가

enum Colors {
    // 기존 유지
    // 추가
    static let overlay = UIColor.black.withAlphaComponent(0.85)
    static let overlayLight = UIColor.black.withAlphaComponent(0.5)
}

enum Fonts {
    // 기존 유지
    // 추가
    static let headlineMono = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
}

enum IconSize {
    static let xs: CGFloat = 12
    static let sm: CGFloat = 16
    static let md: CGFloat = 18
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}
```

---

## 1-2. 드로어 시맨틱 토큰 (Theme+Drawer.swift)

```swift
extension Theme {
    enum Drawer {

        // MARK: - Header

        enum Header {
            static let height: CGFloat = 44
            static let titleFont = Theme.Fonts.headline                 // 17pt semibold
            static let titleColor = Theme.Colors.label
            static let padding = Theme.Spacing.lg                       // 16
        }

        // MARK: - SearchBar

        enum SearchBar {
            static let height: CGFloat = 40
            static let font = Theme.Fonts.body                          // 17pt regular
            static let placeholderColor = Theme.Colors.secondaryLabel
            static let backgroundColor = Theme.Colors.secondaryBackground
            static let cornerRadius = Theme.CornerRadius.medium         // 12
            static let iconSize = Theme.IconSize.lg                     // 20
            static let iconColor = Theme.Colors.secondaryLabel
            static let horizontalPadding = Theme.Spacing.md             // 12
        }

        // MARK: - Cell

        enum Cell {
            static let height: CGFloat = 52
            static let iconSize = Theme.IconSize.xxl                    // 32
            static let iconCornerRadius = Theme.CornerRadius.small      // 8
            static let iconColor = Theme.Colors.primary
            static let iconBackgroundColor = Theme.Colors.secondaryBackground
            static let titleFont = Theme.Fonts.body                     // 17pt regular
            static let titleColor = Theme.Colors.label
            static let subtitleFont = Theme.Fonts.footnote              // 13pt regular
            static let subtitleColor = Theme.Colors.secondaryLabel
            static let horizontalPadding = Theme.Spacing.lg             // 16
            static let iconToTextSpacing = Theme.Spacing.md             // 12
        }

        // MARK: - Favorite Cell (Home 전용)

        enum FavoriteCell {
            static let size: CGFloat = 72
            static let iconSize: CGFloat = 28
            static let nameFont = Theme.Fonts.footnote                  // 13pt regular
            static let nameColor = Theme.Colors.label
            static let backgroundColor = Theme.Colors.secondaryBackground
            static let cornerRadius = Theme.CornerRadius.medium         // 12
            static let interItemSpacing = Theme.Spacing.sm              // 8
        }

        // MARK: - Section Header

        enum SectionHeader {
            static let height: CGFloat = 36
            static let titleFont = Theme.Fonts.headline                 // 17pt semibold
            static let titleColor = Theme.Colors.label
            static let iconSize = Theme.IconSize.sm                     // 16
            static let iconColor = Theme.Colors.primary
            static let iconToTitleSpacing = Theme.Spacing.xs            // 4
            static let horizontalPadding = Theme.Spacing.lg             // 16
        }

        // MARK: - Separator

        enum Separator {
            static let color = Theme.Colors.separator
            static let horizontalInset = Theme.Spacing.lg               // 16
        }

        // MARK: - Layout

        enum Layout {
            static let contentTopPadding = Theme.Spacing.sm             // 8
            static let contentHorizontalPadding = Theme.Spacing.lg      // 16
            static let sectionSpacing = Theme.Spacing.xl                // 24
            static let buttonBottomPadding = Theme.Spacing.lg           // 16
        }
    }
}
```

---

## 1-3. 전체 화면 공통 시맨틱 토큰 (Theme+Component.swift)

```swift
extension Theme {

    // MARK: - Button

    enum Button {
        enum Primary {
            static let height: CGFloat = 48
            static let font = Theme.Fonts.headline                      // 17pt semibold
            static let foregroundColor = UIColor.white
            static let backgroundColor = Theme.Colors.primary
            static let cornerRadius = Theme.CornerRadius.medium         // 12
        }

        enum Secondary {
            static let height: CGFloat = 40
            static let font = Theme.Fonts.subheadline                   // 15pt regular
            static let foregroundColor = Theme.Colors.primary
            static let backgroundColor = Theme.Colors.secondaryBackground
            static let cornerRadius = Theme.CornerRadius.medium         // 12
            static let borderColor = Theme.Colors.primary
            static let borderWidth: CGFloat = 1
        }

        enum Destructive {
            static let height: CGFloat = 44
            static let font = Theme.Fonts.headline                      // 17pt semibold
            static let foregroundColor = UIColor.white
            static let backgroundColor = Theme.Colors.destructive
            static let cornerRadius = Theme.CornerRadius.medium         // 12
        }

        enum Icon {
            static let size: CGFloat = 32
            static let imageSize = Theme.IconSize.md                    // 18
            static let tintColor = Theme.Colors.secondaryLabel
            static let hitAreaMinimum: CGFloat = 44
        }
    }

    // MARK: - Card (지도 위 플로팅 버튼)

    enum Card {
        static let size: CGFloat = 48
        static let iconSize = Theme.IconSize.md                         // 18
        static let cornerRadius: CGFloat = 24                           // 원형
        static let backgroundOpacity: CGFloat = 0.9
        static let backgroundColor = Theme.Colors.secondaryBackground
    }

    // MARK: - Banner (주행 매뉴버 배너)

    enum Banner {
        static let iconSize = Theme.IconSize.xxxl                       // 48
        static let distanceFont = Theme.Fonts.maneuverDistance          // 48pt bold mono
        static let instructionFont = Theme.Fonts.maneuverInstruction   // 24pt semibold
        static let foregroundColor = UIColor.white
        static let backgroundColor = Theme.Colors.overlay              // black 85%
        static let cornerRadius = Theme.CornerRadius.medium             // 12
        static let padding = Theme.Spacing.lg                           // 16
    }

    // MARK: - BottomBar (주행 하단바)

    enum BottomBar {
        static let etaFont = Theme.Fonts.eta                            // 20pt medium mono
        static let etaColor = Theme.Colors.primary
        static let infoFont = Theme.Fonts.body                          // 17pt regular
        static let infoColor = Theme.Colors.label
        static let secondaryInfoColor = Theme.Colors.secondaryLabel
        static let separatorHeight: CGFloat = 20
        static let buttonHeight: CGFloat = 44
        static let cornerRadius = Theme.CornerRadius.large              // 16
        static let padding = Theme.Spacing.lg                           // 16
    }

    // MARK: - Playback (재생 컨트롤)

    enum Playback {
        static let statusFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        static let statusColor = UIColor.white.withAlphaComponent(0.8)
        static let iconSize = Theme.IconSize.xl                         // 24
        static let buttonSize: CGFloat = 44
        static let speedFont = UIFont.systemFont(ofSize: 16, weight: .bold)
        static let backgroundColor = Theme.Colors.overlay              // black 85%
        static let cornerRadius = Theme.CornerRadius.large              // 16
        static let padding = Theme.Spacing.lg                           // 16
        static let trackTintOpacity: CGFloat = 0.3
        static let progressColor = Theme.Colors.success
    }

    // MARK: - Table (설정/개발자도구)

    enum Table {
        static let cellFont = Theme.Fonts.body                          // 17pt regular
        static let cellColor = Theme.Colors.label
        static let detailFont = Theme.Fonts.subheadline                 // 15pt regular
        static let detailColor = Theme.Colors.secondaryLabel
        static let iconPointSize: CGFloat = 17
        static let destructiveColor = Theme.Colors.destructive
    }

    // MARK: - Segment

    enum Segment {
        static let height: CGFloat = 32
        static let selectedTintColor = Theme.Colors.primary
        static let normalTextColor = Theme.Colors.label
        static let selectedTextColor = UIColor.white
    }
}
```

---

## 체크리스트

- [ ] Theme.swift에 IconSize enum, overlay 색상 추가
- [ ] Theme+Drawer.swift 생성 (Header, SearchBar, Cell, FavoriteCell, SectionHeader, Separator, Layout)
- [ ] Theme+Component.swift 생성 (Button, Card, Banner, BottomBar, Playback, Table, Segment)
- [ ] 빌드 확인 (토큰만 정의, 아직 참조하는 코드 없음)
