import UIKit

enum Theme {

    // MARK: - Colors

    enum Colors {
        /// 앱 강조색 — 시스템 블루. 주요 액션·선택/활성·링크에만 절제 사용. (라이트/다크 자동 대응)
        static let accent = UIColor.systemBlue
        /// 옅은 강조 — 선택 배경 등 (accent 12% 틴트)
        static let accentSubtle = UIColor.systemBlue.withAlphaComponent(0.12)
        /// 강조색. `accent`의 별칭 — 기존 호출부 호환용.
        static let primary = accent
        static let background = UIColor.systemBackground
        static let secondaryBackground = UIColor.secondarySystemBackground
        static let surface = UIColor.tertiarySystemBackground
        static let label = UIColor.label
        static let secondaryLabel = UIColor.secondaryLabel
        static let separator = UIColor.separator
        static let destructive = UIColor.systemRed
        static let success = UIColor.systemGreen
        /// 따릉이 브랜드 녹색 (#2EB86B)
        static let bikeBrand = UIColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1)
    }

    // MARK: - Fonts

    enum Fonts {
        /// 디자인 기준 크기를 텍스트 스타일에 맞춰 Dynamic Type로 스케일.
        /// 라벨/버튼에는 `adjustsFontForContentSizeCategory = true`를 함께 설정해야 한다.
        private static func scaled(_ size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        }

        static let largeTitle = scaled(28, weight: .bold, style: .largeTitle)
        static let title = scaled(22, weight: .bold, style: .title2)
        static let headline = scaled(17, weight: .semibold, style: .headline)
        static let body = scaled(17, weight: .regular, style: .body)
        static let callout = scaled(16, weight: .regular, style: .callout)
        static let subheadline = scaled(15, weight: .regular, style: .subheadline)
        static let footnote = scaled(13, weight: .regular, style: .footnote)
        static let caption = scaled(12, weight: .regular, style: .caption1)

        // Navigation-specific (larger for glanceability while driving — 고정 크기 유지)
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

    // MARK: - Icon Size

    enum IconSize {
        static let xs: CGFloat = 12
        static let sm: CGFloat = 16
        static let md: CGFloat = 18
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Shadow

    enum Shadow {
        static let color = UIColor.black.cgColor
        static let opacity: Float = 0.15
        static let offset = CGSize(width: 0, height: 2)
        static let radius: CGFloat = 8
    }
}
