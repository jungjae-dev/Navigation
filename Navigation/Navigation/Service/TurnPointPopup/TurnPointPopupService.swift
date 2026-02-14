import MapKit
import Combine
import CoreLocation

enum PopupType {
    case turn(instruction: String)
    case destination
}

struct PopupConfig {
    let centerCoordinate: CLLocationCoordinate2D
    let routePolyline: MKPolyline
    let vehicleCoordinate: CLLocationCoordinate2D
    let type: PopupType
}

/// Monitors navigation progress and triggers turn point popup display
final class TurnPointPopupService {

    // MARK: - Publishers

    let showPopupPublisher = CurrentValueSubject<Bool, Never>(false)
    let popupConfigPublisher = CurrentValueSubject<PopupConfig?, Never>(nil)

    // MARK: - Configuration

    private let triggerDistance: CLLocationDistance = 300.0
    private let dismissDistance: CLLocationDistance = 30.0

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var currentRoute: MKRoute?
    private var isShowingPopup = false

    // MARK: - Dependencies

    private let guidanceEngine: GuidanceEngine
    private let locationService: LocationService

    // MARK: - Init

    init(guidanceEngine: GuidanceEngine, locationService: LocationService) {
        self.guidanceEngine = guidanceEngine
        self.locationService = locationService
        bind()
    }

    // MARK: - Private

    private func bind() {
        // Track current route
        guidanceEngine.currentRoutePublisher
            .sink { [weak self] route in
                self?.currentRoute = route
            }
            .store(in: &cancellables)

        // Monitor route progress for popup triggers
        guidanceEngine.routeProgressPublisher
            .compactMap { $0 }
            .sink { [weak self] progress in
                self?.evaluatePopup(progress: progress)
            }
            .store(in: &cancellables)
    }

    private func evaluatePopup(progress: RouteProgress) {
        let distance = progress.distanceToNextManeuver

        // Check if we should show popup
        if distance <= triggerDistance && distance > dismissDistance {
            guard let nextStep = progress.nextStep,
                  let route = currentRoute,
                  let location = locationService.locationPublisher.value else {
                return
            }

            if !isShowingPopup {
                isShowingPopup = true

                // Center on the turn point (end of current step / start of next step)
                let turnCoord = nextStep.polyline.coordinates.first
                    ?? progress.currentStep.polyline.coordinates.last
                    ?? location.coordinate

                let config = PopupConfig(
                    centerCoordinate: turnCoord,
                    routePolyline: route.polyline,
                    vehicleCoordinate: location.coordinate,
                    type: .turn(instruction: nextStep.instructions)
                )

                popupConfigPublisher.send(config)
                showPopupPublisher.send(true)
            } else {
                // Update vehicle coordinate while popup is visible
                if let location = locationService.locationPublisher.value,
                   let config = popupConfigPublisher.value {
                    let updatedConfig = PopupConfig(
                        centerCoordinate: config.centerCoordinate,
                        routePolyline: config.routePolyline,
                        vehicleCoordinate: location.coordinate,
                        type: config.type
                    )
                    popupConfigPublisher.send(updatedConfig)
                }
            }
        } else if distance <= dismissDistance || distance > triggerDistance {
            // Dismiss popup when passed the turn or too far
            if isShowingPopup {
                isShowingPopup = false
                showPopupPublisher.send(false)
                popupConfigPublisher.send(nil)
            }
        }
    }

    func reset() {
        isShowingPopup = false
        showPopupPublisher.send(false)
        popupConfigPublisher.send(nil)
        cancellables.removeAll()
    }
}
