import UIKit

final class DrawerContainerManager: NSObject {

    // MARK: - Types

    enum PrimaryContent {
        case home(UIViewController)
        case searchResult(UIViewController)
        case routePreview(UIViewController)
    }

    // MARK: - UI

    private let containerView = DrawerContainerView()
    private let overlayContainerView = DrawerContainerView()
    private weak var parentViewController: UIViewController?

    // MARK: - State

    private(set) var currentPrimary: PrimaryContent?
    private var currentPrimaryVC: UIViewController?
    private var currentOverlayVC: UIViewController?
    private(set) var isVisible = true

    // MARK: - Detent

    private var detents: [DrawerDetent] = []
    private var currentDetent: DrawerDetent?
    private var currentHeight: CGFloat = 200

    // MARK: - Overlay

    private var overlayHeight: CGFloat = 320

    // MARK: - Gesture

    private var panGesture: UIPanGestureRecognizer!
    private var panStartHeight: CGFloat = 0

    // MARK: - Constraints

    private var containerHeightConstraint: NSLayoutConstraint!
    private var containerBottomConstraint: NSLayoutConstraint!
    private var overlayHeightConstraint: NSLayoutConstraint!
    private var overlayBottomConstraint: NSLayoutConstraint!

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

        containerView.translatesAutoresizingMaskIntoConstraints = false
        overlayContainerView.translatesAutoresizingMaskIntoConstraints = false
        overlayContainerView.isHidden = true

        parent.view.addSubview(containerView)
        parent.view.addSubview(overlayContainerView)

        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 200)
        containerBottomConstraint = containerView.bottomAnchor.constraint(
            equalTo: parent.view.bottomAnchor,
            constant: 200 // offscreen initially
        )

        overlayHeightConstraint = overlayContainerView.heightAnchor.constraint(equalToConstant: 320)
        overlayBottomConstraint = overlayContainerView.bottomAnchor.constraint(
            equalTo: parent.view.bottomAnchor,
            constant: 320 // offscreen initially
        )

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            containerBottomConstraint,
            containerHeightConstraint,

            overlayContainerView.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            overlayContainerView.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            overlayBottomConstraint,
            overlayHeightConstraint,
        ])

        containerView.addGestureRecognizer(panGesture)
    }

    // MARK: - Primary Slot

    func setPrimary(
        _ content: PrimaryContent,
        detents: [DrawerDetent],
        initialDetent: DrawerDetent,
        animated: Bool = true
    ) {
        let newVC = viewController(from: content)
        let oldVC = currentPrimaryVC
        let hasOldContent = oldVC != nil

        self.detents = detents
        self.currentDetent = initialDetent
        self.currentPrimary = content

        guard let parent = parentViewController else { return }

        let targetHeight = initialDetent.height(in: parent.view.bounds.height)

        if hasOldContent {
            replacePrimary(oldVC: oldVC, newVC: newVC, targetHeight: targetHeight, animated: animated)
        } else {
            presentPrimary(newVC: newVC, targetHeight: targetHeight, animated: animated)
        }
    }

    // MARK: - Overlay Slot

    func showOverlay(_ viewController: UIViewController, height: CGFloat, animated: Bool = true) {
        guard let parent = parentViewController else { return }

        if let existing = currentOverlayVC {
            removeChildVC(existing, from: overlayContainerView.contentView)
        }

        currentOverlayVC = viewController
        overlayHeight = height

        embedChildVC(viewController, in: overlayContainerView.contentView, parent: parent)
        overlayHeightConstraint.constant = height + parent.view.safeAreaInsets.bottom
        overlayContainerView.isHidden = false

        if animated {
            overlayBottomConstraint.constant = height + parent.view.safeAreaInsets.bottom
            parent.view.layoutIfNeeded()

            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                self.overlayBottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            }
        } else {
            overlayBottomConstraint.constant = 0
        }
    }

    func hideOverlay(animated: Bool = true) {
        guard let parent = parentViewController, let overlayVC = currentOverlayVC else { return }

        let completion = { [weak self] in
            guard let self else { return }
            self.removeChildVC(overlayVC, from: self.overlayContainerView.contentView)
            self.overlayContainerView.isHidden = true
            self.currentOverlayVC = nil
        }

        if animated {
            let offscreen = overlayHeight + parent.view.safeAreaInsets.bottom
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: .curveEaseIn
            ) {
                self.overlayBottomConstraint.constant = offscreen
                parent.view.layoutIfNeeded()
            } completion: { _ in
                completion()
            }
        } else {
            completion()
        }
    }

    var hasOverlay: Bool {
        currentOverlayVC != nil
    }

    // MARK: - Show / Hide All

    func hideAll(animated: Bool = true) {
        guard let parent = parentViewController else { return }
        isVisible = false

        let primaryOffset = currentHeight + parent.view.safeAreaInsets.bottom
        let overlayOffset = overlayHeight + parent.view.safeAreaInsets.bottom

        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: .curveEaseIn
            ) {
                self.containerBottomConstraint.constant = primaryOffset
                if self.currentOverlayVC != nil {
                    self.overlayBottomConstraint.constant = overlayOffset
                }
                parent.view.layoutIfNeeded()
            }
        } else {
            containerBottomConstraint.constant = primaryOffset
            if currentOverlayVC != nil {
                overlayBottomConstraint.constant = overlayOffset
            }
        }
    }

    func showPrimary(animated: Bool = true) {
        guard let parent = parentViewController else { return }
        isVisible = true

        if animated {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                self.containerBottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            } completion: { _ in
                self.onHeightChanged?(self.currentHeight)
            }
        } else {
            containerBottomConstraint.constant = 0
            onHeightChanged?(currentHeight)
        }
    }

    // MARK: - Pan Gesture

    private func setupPanGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let parent = parentViewController else { return }

        let containerHeight = parent.view.bounds.height

        switch gesture.state {
        case .began:
            panStartHeight = currentHeight

        case .changed:
            let translation = gesture.translation(in: parent.view)
            let proposedHeight = panStartHeight - translation.y

            let minHeight = minDetentHeight(in: containerHeight)
            let maxHeight = maxDetentHeight(in: containerHeight)

            // Rubber band outside bounds
            if proposedHeight < minHeight {
                let overscroll = minHeight - proposedHeight
                currentHeight = minHeight - rubberBand(overscroll, dimension: minHeight)
            } else if proposedHeight > maxHeight {
                let overscroll = proposedHeight - maxHeight
                currentHeight = maxHeight + rubberBand(overscroll, dimension: maxHeight)
            } else {
                currentHeight = proposedHeight
            }

            containerHeightConstraint.constant = currentHeight + parent.view.safeAreaInsets.bottom
            onHeightChanged?(currentHeight)

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: parent.view).y
            let targetDetent = resolveTargetDetent(
                currentHeight: currentHeight,
                velocity: velocity,
                containerHeight: containerHeight
            )
            snapToDetent(targetDetent, containerHeight: containerHeight)

        default:
            break
        }
    }

    // MARK: - Detent Resolution

    private func resolveTargetDetent(
        currentHeight: CGFloat,
        velocity: CGFloat,
        containerHeight: CGFloat
    ) -> DrawerDetent {
        guard !detents.isEmpty else { return detents.first ?? .absolute(200, id: "fallback") }

        let sorted = detents.sorted { $0.height(in: containerHeight) < $1.height(in: containerHeight) }

        // Fast swipe: jump to next/previous detent
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

        // Snap to nearest
        return sorted.min(by: {
            abs($0.height(in: containerHeight) - currentHeight) <
                abs($1.height(in: containerHeight) - currentHeight)
        }) ?? sorted[0]
    }

    private func snapToDetent(_ detent: DrawerDetent, containerHeight: CGFloat) {
        guard let parent = parentViewController else { return }

        currentDetent = detent
        let targetHeight = detent.height(in: containerHeight)
        currentHeight = targetHeight

        UIView.animate(
            withDuration: Self.animationDuration,
            delay: 0,
            usingSpringWithDamping: Self.springDamping,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.containerHeightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
            parent.view.layoutIfNeeded()
        } completion: { _ in
            self.onHeightChanged?(targetHeight)
        }
    }

    // MARK: - Private Helpers

    private func presentPrimary(newVC: UIViewController, targetHeight: CGFloat, animated: Bool) {
        guard let parent = parentViewController else { return }

        embedChildVC(newVC, in: containerView.contentView, parent: parent)
        currentPrimaryVC = newVC

        containerHeightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
        currentHeight = targetHeight

        if animated {
            containerBottomConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
            parent.view.layoutIfNeeded()

            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                self.containerBottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            } completion: { _ in
                self.onHeightChanged?(targetHeight)
            }
        } else {
            containerBottomConstraint.constant = 0
            onHeightChanged?(targetHeight)
        }
    }

    private func replacePrimary(
        oldVC: UIViewController?,
        newVC: UIViewController,
        targetHeight: CGFloat,
        animated: Bool
    ) {
        guard let parent = parentViewController else { return }

        let slideDown = { [weak self] (completion: @escaping () -> Void) in
            guard let self else { return }
            let offscreen = self.currentHeight + parent.view.safeAreaInsets.bottom
            UIView.animate(
                withDuration: Self.animationDuration * 0.6,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: .curveEaseIn
            ) {
                self.containerBottomConstraint.constant = offscreen
                parent.view.layoutIfNeeded()
            } completion: { _ in
                completion()
            }
        }

        let slideUp = { [weak self] in
            guard let self else { return }
            self.containerHeightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
            self.currentHeight = targetHeight
            parent.view.layoutIfNeeded()

            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: Self.springDamping,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                self.containerBottomConstraint.constant = 0
                parent.view.layoutIfNeeded()
            } completion: { _ in
                self.onHeightChanged?(targetHeight)
            }
        }

        if animated {
            // Slide down old, swap, slide up new
            slideDown { [weak self] in
                guard let self else { return }
                if let oldVC {
                    self.removeChildVC(oldVC, from: self.containerView.contentView)
                }
                self.embedChildVC(newVC, in: self.containerView.contentView, parent: parent)
                self.currentPrimaryVC = newVC
                slideUp()
            }
        } else {
            if let oldVC {
                removeChildVC(oldVC, from: containerView.contentView)
            }
            embedChildVC(newVC, in: containerView.contentView, parent: parent)
            currentPrimaryVC = newVC
            containerHeightConstraint.constant = targetHeight + parent.view.safeAreaInsets.bottom
            containerBottomConstraint.constant = 0
            currentHeight = targetHeight
            onHeightChanged?(targetHeight)
        }
    }

    private func embedChildVC(_ child: UIViewController, in container: UIView, parent: UIViewController) {
        parent.addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)

        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        child.didMove(toParent: parent)
    }

    private func removeChildVC(_ child: UIViewController, from container: UIView) {
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    private func viewController(from content: PrimaryContent) -> UIViewController {
        switch content {
        case .home(let vc): return vc
        case .searchResult(let vc): return vc
        case .routePreview(let vc): return vc
        }
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
        false
    }

    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }
    }
}
