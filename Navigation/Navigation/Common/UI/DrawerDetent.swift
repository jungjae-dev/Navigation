import UIKit

struct DrawerDetent: Equatable, Hashable {

    let identifier: String
    let heightResolver: (_ containerHeight: CGFloat) -> CGFloat

    static func absolute(_ height: CGFloat, id: String) -> DrawerDetent {
        DrawerDetent(identifier: id) { _ in height }
    }

    static func fractional(_ fraction: CGFloat, id: String) -> DrawerDetent {
        DrawerDetent(identifier: id) { containerHeight in containerHeight * fraction }
    }

    func height(in containerHeight: CGFloat) -> CGFloat {
        heightResolver(containerHeight)
    }

    // MARK: - Equatable & Hashable

    static func == (lhs: DrawerDetent, rhs: DrawerDetent) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
