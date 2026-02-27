import UIKit

enum DrawerScrollHelper {

    private static let detentOrder: [UISheetPresentationController.Detent.Identifier] = [
        .init("small"), .init("drawerMedium"), .init("drawerLarge")
    ]

    private static let velocityThreshold: CGFloat = 0.5

    /// 스크롤이 끝(top/bottom)에 도달했을 때, 속도에 따라 드로어 detent를 전환한다.
    static func handleScrollEdgeTransition(
        scrollView: UIScrollView,
        velocity: CGPoint,
        sheet: UISheetPresentationController?
    ) {
        guard let sheet else { return }

        let offsetY = scrollView.contentOffset.y
        let maxOffsetY = scrollView.contentSize.height - scrollView.bounds.height

        // 상단 도달 + 아래로 스와이프 → 축소
        if offsetY <= 0 && velocity.y < -velocityThreshold {
            if let smaller = previousDetent(from: sheet.selectedDetentIdentifier) {
                sheet.animateChanges {
                    sheet.selectedDetentIdentifier = smaller
                }
            }
            return
        }

        // 하단 도달 + 위로 스와이프 → 확장
        if maxOffsetY > 0 && offsetY >= maxOffsetY && velocity.y > velocityThreshold {
            if let larger = nextDetent(from: sheet.selectedDetentIdentifier) {
                sheet.animateChanges {
                    sheet.selectedDetentIdentifier = larger
                }
            }
        }
    }

    // MARK: - Private

    private static func previousDetent(
        from current: UISheetPresentationController.Detent.Identifier?
    ) -> UISheetPresentationController.Detent.Identifier? {
        guard let current, let index = detentOrder.firstIndex(of: current), index > 0 else {
            return nil
        }
        return detentOrder[index - 1]
    }

    private static func nextDetent(
        from current: UISheetPresentationController.Detent.Identifier?
    ) -> UISheetPresentationController.Detent.Identifier? {
        guard let current, let index = detentOrder.firstIndex(of: current), index + 1 < detentOrder.count else {
            return nil
        }
        return detentOrder[index + 1]
    }
}
