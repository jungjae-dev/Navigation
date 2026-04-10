import SwiftUI
import CoreLocation

/// 상단 회전 안내 배너 (current + next)
struct ManeuverBannerView: View {
    let currentManeuver: ManeuverInfo?
    let nextManeuver: ManeuverInfo?

    var body: some View {
        VStack(spacing: 0) {
            // Current maneuver
            if let maneuver = currentManeuver {
                HStack(spacing: 12) {
                    // 회전 아이콘
                    Image(systemName: maneuver.turnType.iconName)
                        .font(.system(size: Theme.Navigation.Sizes.maneuverIconSize, weight: .bold))
                        .foregroundStyle(Theme.Navigation.Colors.maneuverIcon)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        // 거리
                        Text(formatDistance(maneuver.distance))
                            .font(Theme.Navigation.Fonts.maneuverDistance)
                            .foregroundStyle(Color(.label))

                        // 안내문
                        Text(maneuver.instruction)
                            .font(Theme.Navigation.Fonts.maneuverInstruction)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)

                        // 도로명 (있으면)
                        if let roadName = maneuver.roadName {
                            Text("\(roadName) 방면")
                                .font(Theme.Navigation.Fonts.roadName)
                                .foregroundStyle(Theme.Navigation.Colors.secondaryText)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // Next maneuver (1st와 동일 레이아웃, 크기만 축소)
            if let next = nextManeuver {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: next.turnType.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Navigation.Colors.secondaryText)
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(formatDistance(next.distance))
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.Navigation.Colors.secondaryText)

                        Text(next.instruction)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Navigation.Colors.secondaryText)
                            .lineLimit(1)

                        if let roadName = next.roadName {
                            Text("\(roadName) 방면")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Theme.Navigation.Colors.secondaryText.opacity(0.7))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Theme.Navigation.Colors.bannerBackground)
    }

    // MARK: - Helpers

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private func directionText(_ turnType: TurnType) -> String {
        switch turnType {
        case .straight: return "직진"
        case .leftTurn: return "좌회전"
        case .rightTurn: return "우회전"
        case .uTurn: return "유턴"
        case .leftMerge: return "왼쪽 합류"
        case .rightMerge: return "오른쪽 합류"
        case .leftExit: return "왼쪽 출구"
        case .rightExit: return "오른쪽 출구"
        case .destination: return "도착"
        case .unknown: return ""
        }
    }
}
