import Foundation

final class DrawerListFocusTracker {

    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.15
    private var lastNotifiedIndex: Int = -1

    var onIndexChanged: ((Int) -> Void)?

    func notifyScroll(toIndex index: Int) {
        guard index != lastNotifiedIndex else { return }

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.lastNotifiedIndex = index
            self?.onIndexChanged?(index)
        }
    }

    func reset() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        lastNotifiedIndex = -1
    }
}
