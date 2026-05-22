import SwiftUI

struct RecenterButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "location.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
        }
        .background(.regularMaterial)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
