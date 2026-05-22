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
                            .foregroundStyle(Color(.systemRed))
                        Text(name)
                            .font(Theme.Navigation.Fonts.etaLabel)
                            .foregroundStyle(Theme.Navigation.Colors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            // 우측: 종료 버튼 — 전체 바 높이 기준 vertical center
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
        .padding(.vertical, 8)
        .background(Theme.Navigation.Colors.bottomBarBackground)
    }
}
