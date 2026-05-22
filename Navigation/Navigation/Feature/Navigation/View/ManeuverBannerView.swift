import SwiftUI
import CoreLocation

/// 상단 회전 안내 배너 (current + next)
struct ManeuverBannerView: View {
    let currentManeuver: ManeuverInfo?
    let nextManeuver: ManeuverInfo?

    private let cardOverlap: CGFloat = 14
    private let nextCardHeight: CGFloat = 64   // top padding(cardOverlap+8=22) + icon(32) + bottom padding(10)

    var body: some View {
        VStack(spacing: -cardOverlap) {
            // 1번째 안내 — 앞 (zIndex 높음)
            if let current = currentManeuver {
                currentCard(current)
                    .zIndex(1)
            }

            // 2번째 안내 — 뒤 (zIndex 낮음, 70% 너비, 좌측 정렬)
            if let next = nextManeuver, currentManeuver != nil {
                GeometryReader { geo in
                    nextCard(next)
                        .frame(width: geo.size.width * 0.7)
                }
                .frame(height: nextCardHeight)
                .zIndex(0)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func currentCard(_ maneuver: ManeuverInfo) -> some View {
        HStack(spacing: 14) {
            turnIcon(maneuver.turnType, size: Theme.Navigation.Sizes.maneuverIconSize, weight: Theme.Navigation.Sizes.maneuverIconWeight)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(formatDistance(maneuver.distance))
                    .font(Theme.Navigation.Fonts.maneuverDistance)
                    .foregroundStyle(.white)

                Text(maneuver.instruction)
                    .font(Theme.Navigation.Fonts.maneuverInstruction)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let roadName = maneuver.roadName {
                    Text("\(roadName) 방면")
                        .font(Theme.Navigation.Fonts.roadName)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.Navigation.Colors.bannerPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    @ViewBuilder
    private func nextCard(_ maneuver: ManeuverInfo) -> some View {
        HStack(spacing: 10) {
            // 상단 카드에 가려지는 영역만큼 top padding 추가
            Spacer().frame(width: 0)

            turnIcon(maneuver.turnType, size: 28, weight: .semibold)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)

            Text(formatDistance(maneuver.distance))
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))

            Spacer()
        }
        .padding(.horizontal, 0)
        .padding(.top, cardOverlap + 8)
        .padding(.bottom, 10)
        .background(Theme.Navigation.Colors.bannerSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func turnIcon(_ turnType: TurnType, size: CGFloat, weight: Font.Weight) -> some View {
        Image(systemName: turnType.iconName)
            .font(.system(size: size, weight: weight))
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }
}
