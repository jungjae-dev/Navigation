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

    var topViewController: UIViewController? { topEntry?.viewController }
    var stackDepth: Int { drawerStack.count }

    private var currentHeight: CGFloat {
        get { topEntry?.currentHeight ?? 200 }
        set {
            guard !drawerStack.isEmpty else { return }
            drawerStack[drawerStack.count - 1].currentHeight = newValue
        }
    }

    private var detents: [DrawerDetent] {
        topEntry?.detents ?? []
    }

    private var currentDetent: DrawerDetent? {
        get { topEntry?.activeDetent }
        set {
            guard !drawerStack.isEmpty, let newValue else { return }
            drawerStack[drawerStack.count - 1].activeDetent = newValue
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

        // Move pan gesture to new container
        attachPanGesture(to: entry.containerView)

        if let oldEntry {
            // Slide old down + new up simultaneously
            let oldOffset = oldEntry.currentHeight + parent.view.safeAreaInsets.bottom
            let newOffset = targetHeight + parent.view.safeAreaInsets.bottom

            // Start new container offscreen
            entry.bottomConstraint.constant = newOffset
            parent.view.layoutIfNeeded()

            if animated {
                UIView.animate(
                    withDuration: Self.animationDuration,
                    delay: 0,
                    usingSpringWithDamping: Self.springDamping,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    oldEntry.bottomConstraint.constant = oldOffset
                    entry.bottomConstraint.constant = 0
                    parent.view.layoutIfNeeded()
                } completion: { _ in
                    oldEntry.containerView.isHidden = true
                    self.trackedScrollView = self.findScrollView(in: viewController.view)
                    self.onHeightChanged?(targetHeight)
                }
            } else {
                oldEntry.bottomConstraint.constant = oldOffset
                oldEntry.containerView.isHidden = true
                entry.bottomConstraint.constant = 0
                trackedScrollView = findScrollView(in: viewController.view)
                onHeightChanged?(targetHeight)
            }
        } else {
            // First drawer — slide up
            let offset = targetHeight + parent.view.safeAreaInsets.bottom
            entry.bottomConstraint.constant = offset
            parent.view.layoutIfNeeded()

            if animated {
                UIView.animate(
                    withDuration: Self.animationDuration,
                    delay: 0,
                    usingSpringWithDamping: Self.springDamping,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    entry.bottomConstraint.constant = 0
                    parent.view.layoutIfNeeded()
                } completion: { _ in
                    self.trackedScrollView = self.findScrollView(in: viewController.view)
                    self.onHeightChanged?(targetHeight)
                }
            } else {
                entry.bottomConstraint.constant = 0
                trackedScrollView = findScrollView(in: viewController.view)
                onHeightChanged?(targetHeight)
            }
        }
    }

    func popDrawer(animated: Bool = true) {
        guard drawerStack.count > 1, let parent = parentViewController else { return }

        let topEntry = drawerStack.removeLast()
        let previousEntry = drawerStack.last!

        // Move pan gesture to previous container
        attachPanGesture(to: previousEntry.containerView)

        let topOffset = topEntry.currentHeight + parent.view.safeAreaInsets.bottom
        let prevHeight = previousEntry.currentHeight

        // Un-hide previous, start offscreen
        previousEntry.containerView.isHidden = false
        previousEntry.bottomConstraint.constant = prevHeight + parent.view.safeAreaInsets.bottom
        parent.view.layoutIfNeeded()

        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                topEntry.bottomConstraint.constant = topOffset
                previousEntry.bottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            } completion: { _ in
                self.destroyEntry(topEntry, parent: parent)
                self.trackedScrollView = self.findScrollView(in: previousEntry.viewController.view)
                self.onHeightChanged?(prevHeight)
            }
        } else {
            destroyEntry(topEntry, parent: parent)
            previousEntry.bottomConstraint.constant = 0
            trackedScrollView = findScrollView(in: previousEntry.viewController.view)
            onHeightChanged?(prevHeight)
        }
    }

    func popToRoot(animated: Bool = true) {
        guard drawerStack.count > 1, let parent = parentViewController else { return }

        let topEntry = drawerStack.last!
        let rootEntry = drawerStack[0]

        // Remove intermediates (not top, not root)
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

        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                topEntry.bottomConstraint.constant = topOffset
                rootEntry.bottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            } completion: { _ in
                self.destroyEntry(topEntry, parent: parent)
                self.trackedScrollView = self.findScrollView(in: rootEntry.viewController.view)
                self.onHeightChanged?(rootHeight)
            }
        } else {
            destroyEntry(topEntry, parent: parent)
            rootEntry.bottomConstraint.constant = 0
            trackedScrollView = findScrollView(in: rootEntry.viewController.view)
            onHeightChanged?(rootHeight)
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

        // Clean up all hidden entries (not the old top)
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

            if animated {
                UIView.animate(
                    withDuration: Self.animationDuration,
                    delay: 0,
                    usingSpringWithDamping: Self.springDamping,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    oldTopEntry.bottomConstraint.constant = oldOffset
                    newEntry.bottomConstraint.constant = 0
                    parent.view.layoutIfNeeded()
                } completion: { _ in
                    self.destroyEntry(oldTopEntry, parent: parent)
                    self.trackedScrollView = self.findScrollView(in: viewController.view)
                    self.onHeightChanged?(targetHeight)
                }
            } else {
                destroyEntry(oldTopEntry, parent: parent)
                newEntry.bottomConstraint.constant = 0
                trackedScrollView = findScrollView(in: viewController.view)
                onHeightChanged?(targetHeight)
            }
        } else {
            // No old entry — just slide up
            let offset = targetHeight + parent.view.safeAreaInsets.bottom
            newEntry.bottomConstraint.constant = offset
            parent.view.layoutIfNeeded()

            if animated {
                UIView.animate(
                    withDuration: Self.animationDuration,
                    delay: 0,
                    usingSpringWithDamping: Self.springDamping,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    newEntry.bottomConstraint.constant = 0
                    parent.view.layoutIfNeeded()
                } completion: { _ in
                    self.trackedScrollView = self.findScrollView(in: viewController.view)
                    self.onHeightChanged?(targetHeight)
                }
            } else {
                newEntry.bottomConstraint.constant = 0
                trackedScrollView = findScrollView(in: viewController.view)
                onHeightChanged?(targetHeight)
            }
        }
    }

    // MARK: - Show / Hide All

    func hideAll(animated: Bool = true) {
        guard let parent = parentViewController, let entry = topEntry else { return }
        isVisible = false

        let offset = entry.currentHeight + parent.view.safeAreaInsets.bottom

        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: .curveEaseIn
            ) {
                entry.bottomConstraint.constant = offset
                parent.view.layoutIfNeeded()
            }
        } else {
            entry.bottomConstraint.constant = offset
        }
    }

    func showTop(animated: Bool = true) {
        guard let parent = parentViewController, let entry = topEntry else { return }
        isVisible = true

        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                entry.bottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            } completion: { _ in
                self.onHeightChanged?(entry.currentHeight)
            }
        } else {
            entry.bottomConstraint.constant = 0
            onHeightChanged?(entry.currentHeight)
        }
    }

    func clearAll(animated: Bool = true) {
        guard let parent = parentViewController else { return }

        let topEntry = drawerStack.last

        if animated, let topEntry {
            let offset = topEntry.currentHeight + parent.view.safeAreaInsets.bottom
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: .curveEaseIn
            ) {
                topEntry.bottomConstraint.constant = offset
                parent.view.layoutIfNeeded()
            } completion: { _ in
                for entry in self.drawerStack {
                    self.destroyEntry(entry, parent: parent)
                }
                self.drawerStack.removeAll()
                self.trackedScrollView = nil
            }
        } else {
            for entry in drawerStack {
                destroyEntry(entry, parent: parent)
            }
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
        // Remove from previous container
        panGesture.view?.removeGestureRecognizer(panGesture)
        container.addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let parent = parentViewController, !drawerStack.isEmpty else { return }

        let containerHeight = parent.view.bounds.height
        let scrollView = trackedScrollView
        let velocityY = gesture.velocity(in: parent.view).y
        let entry = drawerStack[drawerStack.count - 1]

        switch gesture.state {
        case .began:
            panStartHeight = entry.currentHeight

            if scrollView == nil {
                isDraggingDrawer = true
            } else {
                let touchInContainer = gesture.location(in: entry.containerView)
                let isOnGrabber = touchInContainer.y < entry.containerView.grabber.frame.maxY

                if isOnGrabber {
                    isDraggingDrawer = true
                } else if isScrollAtTop(scrollView!) && velocityY > 0 {
                    isDraggingDrawer = true
                } else if isScrollAtBottom(scrollView!) && velocityY < 0 {
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
                let atTop = isScrollAtTop(sv)
                let atBottom = isScrollAtBottom(sv)

                if (atTop && velocityY > 0) || (atBottom && velocityY < 0) {
                    isDraggingDrawer = true
                    sv.isScrollEnabled = false
                    sv.contentOffset.y = atTop ? 0 : max(0, sv.contentSize.height - sv.bounds.height)
                    gesture.setTranslation(.zero, in: parent.view)
                    panStartHeight = entry.currentHeight
                }
            }

            guard isDraggingDrawer else { return }

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

            drawerStack[drawerStack.count - 1].currentHeight = newHeight
            entry.heightConstraint.constant = newHeight + parent.view.safeAreaInsets.bottom
            onHeightChanged?(newHeight)

        case .ended, .cancelled:
            scrollView?.isScrollEnabled = true

            if isDraggingDrawer {
                let targetDetent = resolveTargetDetent(
                    currentHeight: entry.currentHeight,
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
        scrollView.contentOffset.y <= 0
    }

    private func isScrollAtBottom(_ scrollView: UIScrollView) -> Bool {
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
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
        let entry = drawerStack[drawerStack.count - 1]

        drawerStack[drawerStack.count - 1].activeDetent = detent
        drawerStack[drawerStack.count - 1].currentHeight = targetHeight

        UIView.animate(
            withDuration: Self.animationDuration,
            delay: 0,
            usingSpringWithDamping: Self.springDamping,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            entry.heightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
            parent.view.layoutIfNeeded()
        } completion: { _ in
            self.onHeightChanged?(targetHeight)
            completion?()
        }
    }

    private func snapToDetent(_ detent: DrawerDetent, containerHeight: CGFloat) {
        guard let parent = parentViewController, !drawerStack.isEmpty else { return }

        let targetHeight = detent.height(in: containerHeight)
        let entry = drawerStack[drawerStack.count - 1]

        drawerStack[drawerStack.count - 1].activeDetent = detent
        drawerStack[drawerStack.count - 1].currentHeight = targetHeight

        UIView.animate(
            withDuration: Self.animationDuration,
            delay: 0,
            usingSpringWithDamping: Self.springDamping,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            entry.heightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
            parent.view.layoutIfNeeded()
        } completion: { _ in
            self.onHeightChanged?(targetHeight)
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

        // Embed VC
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
