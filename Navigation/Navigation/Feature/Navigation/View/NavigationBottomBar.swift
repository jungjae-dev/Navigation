import SwiftUI

/// 하단 바 (목적지명 + ETA + 남은 거리 + 남은 시간 + 종료 버튼)
struct NavigationBottomBar: View {
    let destinationName: String?
    let eta: String
    let remainingDistance: String
    let remainingTime: String
    let onEndNavigation: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 좌측: 수치 + 목적지명
            VStack(spacing: 6) {
                // 1행: 수치 정보
                HStack(spacing: 0) {
                    Text(remainingDistance)
                        .font(Theme.Navigation.Fonts.etaValue)
                        .foregroundStyle(Theme.Navigation.Colors.etaText)
                        .frame(maxWidth: .infinity)

                    Text(remainingTime)
                        .font(Theme.Navigation.Fonts.etaValue)
                        .foregroundStyle(Theme.Navigation.Colors.etaText)
                        .frame(maxWidth: .infinity)

                    Text(eta)
                        .font(Theme.Navigation.Fonts.etaValue)
                        .foregroundStyle(Theme.Navigation.Colors.etaText)
                        .frame(maxWidth: .infinity)
                }

                // 2행: 목적지명
                if let name = destinationName, !name.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Navigation.Colors.secondaryText)
                        Text(name)
                            .font(Theme.Navigation.Fonts.etaLabel)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            // 우측: 종료 버튼 — 전체 바 높이 기준 vertical center
            Button(action: onEndNavigation) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Theme.Navigation.Colors.endButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
    }
}
