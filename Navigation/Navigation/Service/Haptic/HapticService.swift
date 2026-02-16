import UIKit
import Combine

/// Provides haptic feedback for navigation events
final class HapticService {

    // MARK: - Singleton

    static let shared = HapticService()

    // MARK: - Publishers

    let isEnabledPublisher = CurrentValueSubject<Bool, Never>(true)

    // MARK: - Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    // MARK: - Storage

    private let defaults = UserDefaults.standard
    private let enabledKey = "settings_haptic_enabled"

    // MARK: - Init

    private init() {
        if defaults.object(forKey: enabledKey) != nil {
            isEnabledPublisher.send(defaults.bool(forKey: enabledKey))
        } else {
            isEnabledPublisher.send(true)
        }
        prepareGenerators()
    }

    // MARK: - Public

    var isEnabled: Bool {
        isEnabledPublisher.value
    }

    func setEnabled(_ enabled: Bool) {
        isEnabledPublisher.send(enabled)
        defaults.set(enabled, forKey: enabledKey)
    }

    /// Trigger when approaching a maneuver point (turn, exit, etc.)
    func triggerManeuver() {
        guard isEnabled else { return }
        mediumImpact.impactOccurred()
    }

    /// Trigger when the user goes off-route
    func triggerOffRoute() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    /// Trigger when the user arrives at the destination
    func triggerArrival() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }

    /// Trigger when rerouting starts
    func triggerRerouting() {
        guard isEnabled else { return }
        heavyImpact.impactOccurred()
    }

    /// Light feedback for button taps, recenter, etc.
    func triggerLight() {
        guard isEnabled else { return }
        lightImpact.impactOccurred()
    }

    /// Error feedback for failures
    func triggerError() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
    }

    // MARK: - Private

    private func prepareGenerators() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notification.prepare()
    }
}
