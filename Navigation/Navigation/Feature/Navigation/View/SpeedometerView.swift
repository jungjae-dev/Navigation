import SwiftUI
import CoreLocation

/// 속도계
struct SpeedometerView: View {
    let speed: CLLocationSpeed  // m/s

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Int(speed * 3.6))")
                .font(Theme.Navigation.Fonts.speedValue)
                .foregroundStyle(Theme.Navigation.Colors.speedText)
            Text("km/h")
                .font(Theme.Navigation.Fonts.speedUnit)
                .foregroundStyle(Theme.Navigation.Colors.secondaryText)
        }
        .frame(width: Theme.Navigation.Sizes.speedometerSize,
               height: Theme.Navigation.Sizes.speedometerSize)
        .background(Theme.Navigation.Colors.bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
