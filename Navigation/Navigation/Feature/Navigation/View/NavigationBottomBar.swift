import SwiftUI

/// 하단 바 (목적지명 + ETA + 남은 거리 + 남은 시간 + 종료 버튼)
struct NavigationBottomBar: View {
    let destinationName: String?
    let eta: String
    let remainingDistance: String
    let remainingTime: String
    let onEndNavigation: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 목적지명
            if let name = destinationName, !name.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.systemRed))
                    Text(name)
                        .font(Theme.Navigation.Fonts.etaLabel)
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 남은 거리
            VStack(spacing: 2) {
                Text(remainingDistance)
                    .font(Theme.Navigation.Fonts.etaValue)
                    .foregroundStyle(Theme.Navigation.Colors.etaText)
                Text("남은 거리")
                    .font(Theme.Navigation.Fonts.etaLabel)
                    .foregroundStyle(Theme.Navigation.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)

            // 남은 시간
            VStack(spacing: 2) {
                Text(remainingTime)
                    .font(Theme.Navigation.Fonts.etaValue)
                    .foregroundStyle(Theme.Navigation.Colors.etaText)
                Text("남은 시간")
                    .font(Theme.Navigation.Fonts.etaLabel)
                    .foregroundStyle(Theme.Navigation.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)

            // 도착 예정
            VStack(spacing: 2) {
                Text(eta)
                    .font(Theme.Navigation.Fonts.etaValue)
                    .foregroundStyle(Theme.Navigation.Colors.etaText)
                Text("도착")
                    .font(Theme.Navigation.Fonts.etaLabel)
                    .foregroundStyle(Theme.Navigation.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)

            // 종료 버튼
            Button(action: onEndNavigation) {
                Text("안내\n종료")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 52, height: 44)
                    .background(Theme.Navigation.Colors.destructive)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Navigation.Colors.bottomBarBackground)
    }
}
