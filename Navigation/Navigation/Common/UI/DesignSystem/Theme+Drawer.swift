import UIKit

extension Theme {
    enum Drawer {

        // MARK: - Header

        enum Header {
            static let height: CGFloat = 44
            static let titleFont = Theme.Fonts.headline
            static let titleColor = Theme.Colors.label
            static let padding = Theme.Spacing.lg
        }

        // MARK: - SearchBar

        enum SearchBar {
            static let height: CGFloat = 40
            static let font = Theme.Fonts.body
            static let placeholderColor = Theme.Colors.secondaryLabel
            static let backgroundColor = Theme.Colors.secondaryBackground
            static let cornerRadius = Theme.CornerRadius.medium
            static let iconSize = Theme.IconSize.lg
            static let iconColor = Theme.Colors.secondaryLabel
            static let horizontalPadding = Theme.Spacing.md
        }

        // MARK: - Cell

        enum Cell {
            /// 최소 height — Dynamic Type 확대 시 콘텐츠에 맞춰 성장 허용(고정 아님).
            static let height: CGFloat = 52
            static let iconSize = Theme.IconSize.xxl
            static let iconCornerRadius = Theme.CornerRadius.small
            /// 목록 아이콘은 장식 → 중립색(accent 절제). 선택/활성 표시에만 accent 사용.
            static let iconColor = Theme.Colors.secondaryLabel
            static let selectedIconColor = Theme.Colors.accent
            static let iconBackgroundColor = Theme.Colors.secondaryBackground
            static let titleFont = Theme.Fonts.body
            static let titleColor = Theme.Colors.label
            static let subtitleFont = Theme.Fonts.footnote
            static let subtitleColor = Theme.Colors.secondaryLabel
            static let horizontalPadding = Theme.Spacing.lg
            static let iconToTextSpacing = Theme.Spacing.md
        }

        // MARK: - Favorite Cell

        enum FavoriteCell {
            static let size: CGFloat = 72
            static let iconSize: CGFloat = 28
            static let nameFont = Theme.Fonts.footnote
            static let nameColor = Theme.Colors.label
            static let backgroundColor = Theme.Colors.secondaryBackground
            static let cornerRadius = Theme.CornerRadius.medium
            static let interItemSpacing = Theme.Spacing.sm
        }

        // MARK: - Section Header

        enum SectionHeader {
            static let height: CGFloat = 36
            static let titleFont = Theme.Fonts.headline
            static let titleColor = Theme.Colors.label
            static let iconSize = Theme.IconSize.sm
            /// 섹션 아이콘은 장식 → 중립색(accent 절제).
            static let iconColor = Theme.Colors.secondaryLabel
            static let iconToTitleSpacing = Theme.Spacing.xs
            static let horizontalPadding = Theme.Spacing.lg
        }

        // MARK: - Separator

        enum Separator {
            static let color = Theme.Colors.separator
            static let horizontalInset = Theme.Spacing.lg
        }

        // MARK: - Layout

        enum Layout {
            static let contentTopPadding = Theme.Spacing.sm
            static let contentHorizontalPadding = Theme.Spacing.lg
            static let sectionSpacing = Theme.Spacing.xl
            static let buttonBottomPadding = Theme.Spacing.lg
        }
    }
}
