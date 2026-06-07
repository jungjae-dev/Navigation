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

    // MARK: - Standard Presets

    /// 핸들 + 요약만 노출 (홈 기본, 상세 최초 노출)
    static let peek = DrawerDetent.fractional(0.30, id: "peek")
    /// 목록 탐색 (검색 결과, 노선 정류장)
    static let half = DrawerDetent.fractional(0.55, id: "half")
    /// 집중 탐색 / 긴 목록
    static let full = DrawerDetent.fractional(0.92, id: "full")

    /// 화면 대부분이 공유하는 표준 3단 세트
    static let standard: [DrawerDetent] = [.peek, .half, .full]

    // MARK: - Equatable & Hashable

    static func == (lhs: DrawerDetent, rhs: DrawerDetent) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
