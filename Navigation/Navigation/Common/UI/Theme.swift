import UIKit

enum Theme {

    // MARK: - Colors

    enum Colors {
        static let primary = UIColor.systemBlue
        static let background = UIColor.systemBackground
        static let secondaryBackground = UIColor.secondarySystemBackground
        static let surface = UIColor.tertiarySystemBackground
        static let label = UIColor.label
        static let secondaryLabel = UIColor.secondaryLabel
        static let separator = UIColor.separator
        static let destructive = UIColor.systemRed
        static let success = UIColor.systemGreen
    }

    // MARK: - Fonts

    enum Fonts {
        static let largeTitle = UIFont.systemFont(ofSize: 28, weight: .bold)
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let headline = UIFont.systemFont(ofSize: 17, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 17, weight: .regular)
        static let callout = UIFont.systemFont(ofSize: 16, weight: .regular)
        static let subheadline = UIFont.systemFont(ofSize: 15, weight: .regular)
        static let footnote = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let caption = UIFont.systemFont(ofSize: 12, weight: .regular)

        // Navigation-specific (larger for glanceability while driving)
        static let maneuverDistance = UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        static let maneuverInstruction = UIFont.systemFont(ofSize: 24, weight: .semibold)
        static let eta = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 9999
    }

    // MARK: - Shadow

    enum Shadow {
        static let color = UIColor.black.cgColor
        static let opacity: Float = 0.15
        static let offset = CGSize(width: 0, height: 2)
        static let radius: CGFloat = 8
    }
}
