import UIKit

final class DrawerContainerManager: NSObject {

    // MARK: - Types

    struct DrawerEntry {
        let viewController: UIViewController
        let containerView: DrawerContainerView
        let detents: [DrawerDetent]
        var activeDetent: DrawerDetent
        var heightConstraint: NSLayoutConstraint
        var bottomConstraint: NSLayoutConstraint
        var currentHeight: CGFloat
    }

    // MARK: - State

    private weak var parentViewController: UIViewController?
    private(set) var drawerStack: [DrawerEntry] = []
    private(set) var isVisible = true

    // MARK: - Gesture

    private var panGesture: UIPanGestureRecognizer!
    private var panStartHeight: CGFloat = 0

    // MARK: - Scroll Tracking

    private weak var trackedScrollView: UIScrollView?
    private var isDraggingDrawer = false

    // MARK: - Animation

    private static let animationDuration: TimeInterval = 0.3
    private static let springDamping: CGFloat = 0.85
    private static let velocityThreshold: CGFloat = 500

    // MARK: - Callbacks

    var onHeightChanged: ((_ drawerHeight: CGFloat) -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        setupPanGesture()
    }

    // MARK: - Setup

    func install(in parent: UIViewController) {
        parentViewController = parent
    }

    // MARK: - Convenience Accessors (top entry)

    private var topEntry: DrawerEntry? { drawerStack.last }
    private var topContainer: DrawerContainerView? { topEntry?.containerView }
    private var topIndex: Int { drawerStack.count - 1 }

    var topViewController: UIViewController? { topEntry?.viewController }
    var stackDepth: Int { drawerStack.count }

    private var currentHeight: CGFloat {
        get { topEntry?.currentHeight ?? 200 }
        set {
            guard !drawerStack.isEmpty else { return }
            drawerStack[topIndex].currentHeight = newValue
        }
    }

    private var detents: [DrawerDetent] {
        topEntry?.detents ?? []
    }

    private var currentDetent: DrawerDetent? {
        get { topEntry?.activeDetent }
        set {
            guard !drawerStack.isEmpty, let newValue else { return }
            drawerStack[topIndex].activeDetent = newValue
        }
    }

    func contains(_ viewController: UIViewController) -> Bool {
        drawerStack.contains { $0.viewController === viewController }
    }

    // MARK: - Stack Operations

    func pushDrawer(
        _ viewController: UIViewController,
        detents: [DrawerDetent],
        initialDetent: DrawerDetent,
        animated: Bool = true
    ) {
        guard let parent = parentViewController else { return }

        let targetHeight = initialDetent.height(in: parent.view.bounds.height)
        let entry = createEntry(
            viewController: viewController,
            detents: detents,
            initialDetent: initialDetent,
            targetHeight: targetHeight,
            parent: parent
        )

        let oldEntry = drawerStack.last
        drawerStack.append(entry)

        attachPanGesture(to: entry.containerView)

        if let oldEntry {
            let oldOffset = oldEntry.currentHeight + parent.view.safeAreaInsets.bottom
            let newOffset = targetHeight + parent.view.safeAreaInsets.bottom

            entry.bottomConstraint.constant = newOffset
            parent.view.layoutIfNeeded()

            animateTransition(in: parent, animated: animated) {
                oldEntry.bottomConstraint.constant = oldOffset
                entry.bottomConstraint.constant = 0
            } completion: {
                oldEntry.containerView.isHidden = true
                self.trackedScrollView = self.findScrollView(in: viewController.view)
                self.onHeightChanged?(targetHeight)
            }
        } else {
            let offset = targetHeight + parent.view.safeAreaInsets.bottom
            entry.bottomConstraint.constant = offset
            parent.view.layoutIfNeeded()

            animateTransition(in: parent, animated: animated) {
                entry.bottomConstraint.constant = 0
            } completion: {
                self.trackedScrollView = self.findScrollView(in: viewController.view)
                self.onHeightChanged?(targetHeight)
            }
        }
    }

    func popDrawer(animated: Bool = true) {
        guard drawerStack.count > 1, let parent = parentViewController else { return }

        let topEntry = drawerStack.removeLast()
        let previousEntry = drawerStack.last!

        attachPanGesture(to: previousEntry.containerView)

        let topOffset = topEntry.currentHeight + parent.view.safeAreaInsets.bottom
        let prevHeight = previousEntry.currentHeight

        previousEntry.containerView.isHidden = false
        previousEntry.bottomConstraint.constant = prevHeight + parent.view.safeAreaInsets.bottom
        parent.view.layoutIfNeeded()

        animateTransition(in: parent, animated: animated) {
            topEntry.bottomConstraint.constant = topOffset
            previousEntry.bottomConstraint.constant = 0
        } completion: {
            self.destroyEntry(topEntry, parent: parent)
            self.trackedScrollView = self.findScrollView(in: previousEntry.viewController.view)
            self.onHeightChanged?(prevHeight)
        }
    }

    func popToRoot(animated: Bool = true) {
        guard drawerStack.count > 1, let parent = parentViewController else { return }

        let topEntry = drawerStack.last!
        let rootEntry = drawerStack[0]

        for i in 1..<(drawerStack.count - 1) {
            destroyEntry(drawerStack[i], parent: parent)
        }

        drawerStack = [rootEntry]

        attachPanGesture(to: rootEntry.containerView)

        let topOffset = topEntry.currentHeight + parent.view.safeAreaInsets.bottom
        let rootHeight = rootEntry.currentHeight

        rootEntry.containerView.isHidden = false
        rootEntry.bottomConstraint.constant = rootHeight + parent.view.safeAreaInsets.bottom
        parent.view.layoutIfNeeded()

        animateTransition(in: parent, animated: animated) {
            topEntry.bottomConstraint.constant = topOffset
            rootEntry.bottomConstraint.constant = 0
        } completion: {
            self.destroyEntry(topEntry, parent: parent)
            self.trackedScrollView = self.findScrollView(in: rootEntry.viewController.view)
            self.onHeightChanged?(rootHeight)
        }
    }

    func replaceStack(
        with viewController: UIViewController,
        detents: [DrawerDetent],
        initialDetent: DrawerDetent,
        animated: Bool = true
    ) {
        guard let parent = parentViewController else { return }

        let oldTopEntry = drawerStack.last

        for entry in drawerStack where entry.containerView !== oldTopEntry?.containerView {
            destroyEntry(entry, parent: parent)
        }

        let targetHeight = initialDetent.height(in: parent.view.bounds.height)
        let newEntry = createEntry(
            viewController: viewController,
            detents: detents,
            initialDetent: initialDetent,
            targetHeight: targetHeight,
            parent: parent
        )

        drawerStack = [newEntry]
        attachPanGesture(to: newEntry.containerView)

        if let oldTopEntry {
            let oldOffset = oldTopEntry.currentHeight + parent.view.safeAreaInsets.bottom
            let newOffset = targetHeight + parent.view.safeAreaInsets.bottom

            newEntry.bottomConstraint.constant = newOffset
            parent.view.layoutIfNeeded()

            animateTransition(in: parent, animated: animated) {
                oldTopEntry.bottomConstraint.constant = oldOffset
                newEntry.bottomConstraint.constant = 0
            } completion: {
                self.destroyEntry(oldTopEntry, parent: parent)
                self.trackedScrollView = self.findScrollView(in: viewController.view)
                self.onHeightChanged?(targetHeight)
            }
        } else {
            let offset = targetHeight + parent.view.safeAreaInsets.bottom
            newEntry.bottomConstraint.constant = offset
            parent.view.layoutIfNeeded()

            animateTransition(in: parent, animated: animated) {
                newEntry.bottomConstraint.constant = 0
            } completion: {
                self.trackedScrollView = self.findScrollView(in: viewController.view)
                self.onHeightChanged?(targetHeight)
            }
        }
    }

    // MARK: - Show / Hide All

    func hideAll(animated: Bool = true) {
        guard let parent = parentViewController, let entry = topEntry else { return }
        isVisible = false

        let offset = entry.currentHeight + parent.view.safeAreaInsets.bottom

        animateTransition(in: parent, damping: 1.0, options: .curveEaseIn, animated: animated) {
            entry.bottomConstraint.constant = offset
        }
    }

    func showTop(animated: Bool = true) {
        guard let parent = parentViewController, let entry = topEntry else { return }
        isVisible = true

        animateTransition(in: parent, animated: animated) {
            entry.bottomConstraint.constant = 0
        } completion: {
            self.onHeightChanged?(entry.currentHeight)
        }
    }

    func clearAll(animated: Bool = true) {
        guard let parent = parentViewController else { return }

        let topEntry = drawerStack.last

        if let topEntry {
            let offset = topEntry.currentHeight + parent.view.safeAreaInsets.bottom

            animateTransition(in: parent, damping: 1.0, options: .curveEaseIn, animated: animated) {
                topEntry.bottomConstraint.constant = offset
            } completion: {
                for entry in self.drawerStack {
                    self.destroyEntry(entry, parent: parent)
                }
                self.drawerStack.removeAll()
                self.trackedScrollView = nil
            }
        } else {
            drawerStack.removeAll()
            trackedScrollView = nil
        }

        isVisible = false
    }

    // MARK: - Pan Gesture

    private func setupPanGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
    }

    private func attachPanGesture(to container: DrawerContainerView) {
        panGesture.view?.removeGestureRecognizer(panGesture)
        container.addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let parent = parentViewController, !drawerStack.isEmpty else { return }

        let containerHeight = parent.view.bounds.height
        let scrollView = trackedScrollView
        let velocityY = gesture.velocity(in: parent.view).y

        switch gesture.state {
        case .began:
            panStartHeight = drawerStack[topIndex].currentHeight

            if scrollView == nil {
                isDraggingDrawer = true
            } else {
                let initialTouch = drawerStack[topIndex].containerView.initialTouchPoint
                    ?? gesture.location(in: drawerStack[topIndex].containerView)
                let scrollOriginInContainer = scrollView!.superview?.convert(
                    scrollView!.frame.origin, to: drawerStack[topIndex].containerView
                )
                let isOnHeader = scrollOriginInContainer.map { initialTouch.y < $0.y } ?? false
                let atTop = isScrollAtTop(scrollView!)
                let atBottom = isScrollAtBottom(scrollView!)

                if isOnHeader {
                    isDraggingDrawer = true
                } else if atTop && velocityY > 0 {
                    isDraggingDrawer = true
                } else if atBottom && velocityY < 0 {
                    isDraggingDrawer = true
                } else {
                    isDraggingDrawer = false
                }
            }

            if isDraggingDrawer {
                scrollView?.isScrollEnabled = false
            }

        case .changed:
            if !isDraggingDrawer, let sv = scrollView {
                let shouldHandoff = (isScrollAtTop(sv) && velocityY > 0)
                    || (isScrollAtBottom(sv) && velocityY < 0)

                if shouldHandoff {
                    isDraggingDrawer = true
                    sv.isScrollEnabled = false
                    panStartHeight = drawerStack[topIndex].currentHeight
                    gesture.setTranslation(.zero, in: parent.view)
                } else {
                    return
                }
            }

            let translation = gesture.translation(in: parent.view)
            let proposedHeight = panStartHeight - translation.y

            let minH = minDetentHeight(in: containerHeight)
            let maxH = maxDetentHeight(in: containerHeight)

            let newHeight: CGFloat
            if proposedHeight < minH {
                let overscroll = minH - proposedHeight
                newHeight = minH - rubberBand(overscroll, dimension: minH)
            } else if proposedHeight > maxH {
                let overscroll = proposedHeight - maxH
                newHeight = maxH + rubberBand(overscroll, dimension: maxH)
            } else {
                newHeight = proposedHeight
            }

            drawerStack[topIndex].currentHeight = newHeight
            drawerStack[topIndex].heightConstraint.constant = newHeight + parent.view.safeAreaInsets.bottom
            onHeightChanged?(newHeight)

        case .ended, .cancelled:
            scrollView?.isScrollEnabled = true

            if isDraggingDrawer {
                let targetDetent = resolveTargetDetent(
                    currentHeight: drawerStack[topIndex].currentHeight,
                    velocity: velocityY,
                    containerHeight: containerHeight
                )
                snapToDetent(targetDetent, containerHeight: containerHeight)
            }
            isDraggingDrawer = false

        default:
            break
        }
    }

    // MARK: - Scroll Boundary Helpers

    private func isScrollAtTop(_ scrollView: UIScrollView) -> Bool {
        scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
    }

    private func isScrollAtBottom(_ scrollView: UIScrollView) -> Bool {
        let inset = scrollView.adjustedContentInset
        let maxOffset = scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
        guard maxOffset > 0 else { return true }
        return scrollView.contentOffset.y >= maxOffset - 1
    }

    // MARK: - Detent Resolution

    private func resolveTargetDetent(
        currentHeight: CGFloat,
        velocity: CGFloat,
        containerHeight: CGFloat
    ) -> DrawerDetent {
        let currentDetents = detents
        guard !currentDetents.isEmpty else { return .absolute(200, id: "fallback") }

        let sorted = currentDetents.sorted { $0.height(in: containerHeight) < $1.height(in: containerHeight) }

        if velocity < -Self.velocityThreshold, let current = currentDetent {
            if let nextIndex = sorted.firstIndex(of: current).map({ $0 + 1 }),
               nextIndex < sorted.count {
                return sorted[nextIndex]
            }
        } else if velocity > Self.velocityThreshold, let current = currentDetent {
            if let prevIndex = sorted.firstIndex(of: current).map({ $0 - 1 }),
               prevIndex >= 0 {
                return sorted[prevIndex]
            }
        }

        return sorted.min(by: {
            abs($0.height(in: containerHeight) - currentHeight) <
                abs($1.height(in: containerHeight) - currentHeight)
        }) ?? sorted[0]
    }

    func snapToDetent(id: String, completion: (() -> Void)? = nil) {
        guard let parent = parentViewController, !drawerStack.isEmpty else { return }
        let containerHeight = parent.view.bounds.height

        guard let detent = detents.first(where: { $0.identifier == id }) else { return }

        let targetHeight = detent.height(in: containerHeight)

        drawerStack[topIndex].activeDetent = detent
        drawerStack[topIndex].currentHeight = targetHeight

        animateTransition(in: parent, animated: true) {
            self.drawerStack[self.topIndex].heightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
        } completion: {
            self.onHeightChanged?(targetHeight)
            completion?()
        }
    }

    private func snapToDetent(_ detent: DrawerDetent, containerHeight: CGFloat) {
        guard let parent = parentViewController, !drawerStack.isEmpty else { return }

        let targetHeight = detent.height(in: containerHeight)

        drawerStack[topIndex].activeDetent = detent
        drawerStack[topIndex].currentHeight = targetHeight

        animateTransition(in: parent, animated: true) {
            self.drawerStack[self.topIndex].heightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
        } completion: {
            self.onHeightChanged?(targetHeight)
        }
    }

    // MARK: - Animation Helper

    private func animateTransition(
        in parent: UIViewController,
        damping: CGFloat = springDamping,
        options: UIView.AnimationOptions = .curveEaseOut,
        animated: Bool,
        animations: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: damping,
                initialSpringVelocity: 0,
                options: options
            ) {
                animations()
                parent.view.layoutIfNeeded()
            } completion: { _ in
                completion?()
            }
        } else {
            animations()
            parent.view.layoutIfNeeded()
            completion?()
        }
    }

    // MARK: - Entry Lifecycle

    private func createEntry(
        viewController: UIViewController,
        detents: [DrawerDetent],
        initialDetent: DrawerDetent,
        targetHeight: CGFloat,
        parent: UIViewController
    ) -> DrawerEntry {
        let container = DrawerContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(container)

        let heightConstraint = container.heightAnchor.constraint(
            equalToConstant: targetHeight + parent.view.safeAreaInsets.bottom
        )
        let bottomConstraint = container.bottomAnchor.constraint(
            equalTo: parent.view.bottomAnchor,
            constant: targetHeight + parent.view.safeAreaInsets.bottom // offscreen
        )

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            bottomConstraint,
            heightConstraint,
        ])

        parent.addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        container.contentView.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: container.contentView.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
        ])

        viewController.didMove(toParent: parent)

        return DrawerEntry(
            viewController: viewController,
            containerView: container,
            detents: detents,
            activeDetent: initialDetent,
            heightConstraint: heightConstraint,
            bottomConstraint: bottomConstraint,
            currentHeight: targetHeight
        )
    }

    private func destroyEntry(_ entry: DrawerEntry, parent: UIViewController) {
        entry.viewController.willMove(toParent: nil)
        entry.viewController.view.removeFromSuperview()
        entry.viewController.removeFromParent()
        entry.containerView.removeFromSuperview()
    }

    // MARK: - Helpers

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func minDetentHeight(in containerHeight: CGFloat) -> CGFloat {
        detents.map { $0.height(in: containerHeight) }.min() ?? 200
    }

    private func maxDetentHeight(in containerHeight: CGFloat) -> CGFloat {
        detents.map { $0.height(in: containerHeight) }.max() ?? 200
    }

    private func rubberBand(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        let coefficient: CGFloat = 0.55
        return (1.0 - (1.0 / ((offset * coefficient / dimension) + 1.0))) * dimension
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DrawerContainerManager: UIGestureRecognizerDelegate {

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        MainActor.assumeIsolated {
            if otherGestureRecognizer.view is UIScrollView {
                return true
            }
            return false
        }
    }

    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }
    }
}
