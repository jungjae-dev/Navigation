import SwiftUI

extension Theme {

    /// 주행 화면 전용 디자인 토큰 (다크모드 자동 대응)
    enum Navigation {

        // MARK: - Colors

        enum Colors {
            static let bannerBackground = Color(.systemBackground)
            static let bannerPrimary = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.05, green: 0.20, blue: 0.50, alpha: 1)
                    : UIColor(red: 0.10, green: 0.37, blue: 0.75, alpha: 1)
            })
            static let bannerSecondary = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.10, green: 0.28, blue: 0.60, alpha: 1)
                    : UIColor(red: 0.22, green: 0.49, blue: 0.87, alpha: 1)
            })
            static let bottomBarBackground = Color(.systemBackground)
            static let routePolyline = Color.blue
            static let maneuverIcon = Color.blue

            static let speedText = Color(.label)
            static let etaText = Color(.label)
            static let secondaryText = Color(.secondaryLabel)
            static let endButton = Color(.systemGray2)
            static let destructive = Color(.systemRed)
            static let gpsIcon = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1)
                    : UIColor(red: 0.10, green: 0.37, blue: 0.75, alpha: 1)
            }
            static let gpsWarning = Color(.systemOrange)
            static let rerouteBanner = Color(.systemYellow).opacity(0.9)
            static let arrivalBackground = Color(.systemBackground)
        }

        // MARK: - Fonts (SwiftUI)

        enum Fonts {
            static let maneuverDistance = Font.system(size: 36, weight: .bold).monospacedDigit()
            static let maneuverInstruction = Font.system(size: 18, weight: .semibold)
            static let nextManeuver = Font.system(size: 14, weight: .regular)
            static let roadName = Font.system(size: 14, weight: .medium)
            static let speedValue = Font.system(size: 28, weight: .bold).monospacedDigit()
            static let speedUnit = Font.system(size: 12, weight: .regular)
            static let etaValue = Font.system(size: 17, weight: .semibold).monospacedDigit()
            static let etaLabel = Font.system(size: 13, weight: .regular)
            static let arrivalTitle = Font.system(size: 22, weight: .bold)
            static let countdownText = Font.system(size: 17, weight: .medium)
        }

        // MARK: - Sizes

        enum Sizes {
            static let bannerHeight: CGFloat = 110
            static let bottomBarHeight: CGFloat = 80
            static let maneuverIconSize: CGFloat = 44
            static let maneuverIconWeight: Font.Weight = .black
            static let speedometerSize: CGFloat = 70
            static let buttonSize: CGFloat = 44
        }
    }
}
