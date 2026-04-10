import SwiftUI
import Combine

/// 도착 팝업 (5초 카운트다운 + 종료 버튼)
struct ArrivalPopupView: View {
    let onDismiss: () -> Void

    @State private var countdown: Int = 5
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 40))
                .foregroundStyle(Color(.systemGreen))

            Text("목적지에 도착했습니다")
                .font(Theme.Navigation.Fonts.arrivalTitle)
                .foregroundStyle(Color(.label))

            Button(action: onDismiss) {
                Text("주행 종료 (\(countdown))")
                    .font(Theme.Navigation.Fonts.countdownText)
                    .foregroundStyle(.white)
                    .frame(width: 160, height: 44)
                    .background(Theme.Navigation.Colors.destructive)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(24)
        .background(Theme.Navigation.Colors.arrivalBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onReceive(timer) { _ in
            if countdown > 1 {
                countdown -= 1
            } else {
                onDismiss()
            }
        }
    }
}
