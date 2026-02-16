import Foundation
import Combine
import MapKit
import CoreLocation

final class NavigationViewModel {

    // MARK: - UI Publishers

    let maneuverInstruction = CurrentValueSubject<String, Never>("경로를 따라 이동하세요")
    let maneuverDistance = CurrentValueSubject<String, Never>("--")
    let maneuverIconName = CurrentValueSubject<String, Never>("arrow.up")
    let etaText = CurrentValueSubject<String, Never>("--:--")
    let remainingDistance = CurrentValueSubject<String, Never>("-- km")
    let remainingTime = CurrentValueSubject<String, Never>("-- 분")
    let showRecenterButton = CurrentValueSubject<Bool, Never>(false)
    let navigationState = CurrentValueSubject<NavigationState, Never>(.preparing)
    let errorMessage = CurrentValueSubject<String?, Never>(nil)

    // MARK: - Dependencies

    private let guidanceEngine: GuidanceEngine
    private let mapInterpolator: MapInterpolator
    private let turnPointPopupService: TurnPointPopupService
    private let locationService: LocationService
    private let mapCamera: MapCamera

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var route: MKRoute?
    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()

    // MARK: - Init

    init(
        guidanceEngine: GuidanceEngine,
        mapInterpolator: MapInterpolator,
        turnPointPopupService: TurnPointPopupService,
        locationService: LocationService,
        mapCamera: MapCamera
    ) {
        self.guidanceEngine = guidanceEngine
        self.mapInterpolator = mapInterpolator
        self.turnPointPopupService = turnPointPopupService
        self.locationService = locationService
        self.mapCamera = mapCamera

        bindGuidanceEngine()
        bindMapCamera()
        bindErrors()
    }

    // MARK: - Public

    /// The currently active route
    var currentRoute: MKRoute? { route }

    func startNavigation(with route: MKRoute, transportMode: TransportMode = .automobile) {
        self.route = route
        guidanceEngine.startNavigation(with: route, transportMode: transportMode)

        // Start interpolation on location updates
        locationService.locationPublisher
            .compactMap { $0 }
            .sink { [weak self] location in
                let heading = self?.locationService.headingPublisher.value?.trueHeading ?? location.course
                self?.mapInterpolator.updateTarget(location: location, heading: heading)
            }
            .store(in: &cancellables)
    }

    func stopNavigation() {
        guidanceEngine.stopNavigation()
        mapInterpolator.stop()
        turnPointPopupService.reset()
        cancellables.removeAll()
    }

    func recenterMap() {
        mapCamera.enableAutoTracking()
    }

    func handleUserMapInteraction() {
        mapCamera.disableAutoTracking()
    }

    // MARK: - Binding

    private func bindGuidanceEngine() {
        // Navigation state
        guidanceEngine.navigationStatePublisher
            .sink { [weak self] state in
                self?.navigationState.send(state)
            }
            .store(in: &cancellables)

        // Route progress → formatted UI strings
        guidanceEngine.routeProgressPublisher
            .compactMap { $0 }
            .sink { [weak self] progress in
                self?.updateUI(with: progress)
            }
            .store(in: &cancellables)

        // Current step → maneuver instruction
        guidanceEngine.currentStepPublisher
            .compactMap { $0 }
            .sink { [weak self] step in
                self?.updateManeuver(with: step)
            }
            .store(in: &cancellables)
    }

    private func bindErrors() {
        guidanceEngine.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.errorMessage.send("재경로 탐색 실패. 기존 경로로 안내합니다.")
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.errorMessage.send(nil)
                }
            }
            .store(in: &cancellables)
    }

    private func bindMapCamera() {
        mapCamera.isAutoTrackingPublisher
            .map { !$0 } // Show recenter when NOT auto-tracking
            .sink { [weak self] show in
                self?.showRecenterButton.send(show)
            }
            .store(in: &cancellables)
    }

    // MARK: - UI Updates

    private func updateUI(with progress: RouteProgress) {
        // Distance to next maneuver
        maneuverDistance.send(formatDistance(progress.distanceToNextManeuver))

        // Remaining distance
        remainingDistance.send(formatDistance(progress.distanceRemaining))

        // Remaining time
        remainingTime.send(formatTime(progress.timeRemaining))

        // ETA
        etaText.send(dateFormatter.string(from: progress.estimatedArrivalTime))

        // Update icon based on next step instruction
        if let nextStep = progress.nextStep {
            let iconName = GuidanceTextBuilder.iconNameForInstruction(nextStep.instructions)
            maneuverIconName.send(iconName)
        }
    }

    private func updateManeuver(with step: MKRoute.Step) {
        let instruction = step.instructions.isEmpty
            ? "경로를 따라 이동하세요"
            : step.instructions
        maneuverInstruction.send(instruction)
    }

    // MARK: - Formatting

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            let km = meters / 1000.0
            return String(format: "%.1fkm", km)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 {
            return "\(max(1, totalMinutes))분"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours)시간"
            }
            return "\(hours)시간 \(minutes)분"
        }
    }
}
