import UIKit

extension Theme {

    // MARK: - Button

    enum Button {
        enum Primary {
            static let height: CGFloat = 48
            static let font = Theme.Fonts.headline
            static let foregroundColor = UIColor.white
            static let backgroundColor = Theme.Colors.primary
            static let cornerRadius = Theme.CornerRadius.medium
        }

        enum Secondary {
            static let height: CGFloat = 40
            static let font = Theme.Fonts.subheadline
            static let foregroundColor = Theme.Colors.primary
            static let backgroundColor = Theme.Colors.secondaryBackground
            static let cornerRadius = Theme.CornerRadius.medium
            static let borderColor = Theme.Colors.primary
            static let borderWidth: CGFloat = 1
        }

        enum Destructive {
            static let height: CGFloat = 44
            static let font = Theme.Fonts.headline
            static let foregroundColor = UIColor.white
            static let backgroundColor = Theme.Colors.destructive
            static let cornerRadius = Theme.CornerRadius.medium
        }

        enum Icon {
            static let size: CGFloat = 32
            static let imageSize = Theme.IconSize.md
            static let tintColor = Theme.Colors.secondaryLabel
            static let hitAreaMinimum: CGFloat = 44
        }
    }

    // MARK: - Card (Map Floating Buttons)

    enum Card {
        static let size: CGFloat = 48
        static let iconSize = Theme.IconSize.md
        static let cornerRadius: CGFloat = 24
        static let backgroundOpacity: CGFloat = 0.9
        static let backgroundColor = Theme.Colors.secondaryBackground
    }

    // MARK: - Banner (Navigation Maneuver)

    enum Banner {
        static let iconSize = Theme.IconSize.xxxl
        static let distanceFont = Theme.Fonts.maneuverDistance
        static let instructionFont = Theme.Fonts.maneuverInstruction
        static let foregroundColor = UIColor.white
        static let backgroundColor = UIColor.black.withAlphaComponent(0.85)
        static let cornerRadius = Theme.CornerRadius.medium
        static let padding = Theme.Spacing.lg
    }

    // MARK: - BottomBar (Navigation Info)

    enum BottomBar {
        static let etaFont = Theme.Fonts.eta
        static let etaColor = Theme.Colors.primary
        static let infoFont = Theme.Fonts.body
        static let infoColor = Theme.Colors.label
        static let secondaryInfoColor = Theme.Colors.secondaryLabel
        static let separatorHeight: CGFloat = 20
        static let buttonHeight: CGFloat = 44
        static let cornerRadius = Theme.CornerRadius.large
        static let padding = Theme.Spacing.lg
    }

    // MARK: - Playback Control

    enum Playback {
        static let statusFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        static let statusColor = UIColor.white.withAlphaComponent(0.8)
        static let iconSize = Theme.IconSize.xl
        static let buttonSize: CGFloat = 44
        static let speedFont = UIFont.systemFont(ofSize: 16, weight: .bold)
        static let backgroundColor = UIColor.black.withAlphaComponent(0.85)
        static let cornerRadius = Theme.CornerRadius.large
        static let padding = Theme.Spacing.lg
        static let trackTintOpacity: CGFloat = 0.3
        static let progressColor = Theme.Colors.success
    }

    // MARK: - Table (Settings / DevTools)

    enum Table {
        static let cellFont = Theme.Fonts.body
        static let cellColor = Theme.Colors.label
        static let detailFont = Theme.Fonts.subheadline
        static let detailColor = Theme.Colors.secondaryLabel
        static let iconPointSize: CGFloat = 17
        static let destructiveColor = Theme.Colors.destructive
    }

    // MARK: - Segment Control

    enum Segment {
        static let height: CGFloat = 32
        static let selectedTintColor = Theme.Colors.primary
        static let normalTextColor = Theme.Colors.label
        static let selectedTextColor = UIColor.white
    }
}
