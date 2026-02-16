import UIKit
import CarPlay
import MapKit
import Combine

final class CarPlayNavigationHandler {

    // MARK: - Properties

    private var navigationSession: CPNavigationSession?
    private var cancellables = Set<AnyCancellable>()
    private var addedManeuvers: [CPManeuver] = []

    // MARK: - Public

    func startNavigation(
        trip: CPTrip,
        mapTemplate: CPMapTemplate,
        guidanceEngine: GuidanceEngine
    ) {
        // Stop any existing session
        stopNavigation()

        // Start CPNavigationSession
        let session = mapTemplate.startNavigationSession(for: trip)
        session.pauseTrip(for: .loading, description: "경로 준비 중", turnCardColor: nil)
        self.navigationSession = session

        // Subscribe to guidance updates
        bindGuidanceEngine(guidanceEngine, session: session)
    }

    func stopNavigation() {
        cancellables.removeAll()
        navigationSession?.finishTrip()
        navigationSession = nil
        addedManeuvers = []
    }

    // MARK: - Guidance Binding

    private func bindGuidanceEngine(_ engine: GuidanceEngine, session: CPNavigationSession) {
        // Navigation State
        engine.navigationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleNavigationState(state, session: session)
            }
            .store(in: &cancellables)

        // Route Progress → CPRouteInformation
        engine.routeProgressPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.updateRouteInformation(from: progress, session: session)
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation State

    private func handleNavigationState(_ state: NavigationState, session: CPNavigationSession) {
        switch state {
        case .navigating:
            break // Normal operation

        case .rerouting:
            session.pauseTrip(
                for: .rerouting,
                description: "경로 재탐색 중",
                turnCardColor: nil
            )

        case .arrived:
            session.finishTrip()
            stopNavigation()

        case .stopped:
            session.cancelTrip()
            stopNavigation()

        case .preparing:
            break

        case .parkingApproach:
            break // Continue normal navigation on CarPlay
        }
    }

    // MARK: - Route Information Updates

    private func updateRouteInformation(from progress: RouteProgress, session: CPNavigationSession) {
        // Build current maneuver
        var currentManeuvers: [CPManeuver] = []
        var upcomingManeuvers: [CPManeuver] = []

        if let nextStep = progress.nextStep {
            let maneuver = buildManeuver(from: nextStep, distance: progress.distanceToNextManeuver)
            currentManeuvers.append(maneuver)
            upcomingManeuvers.append(maneuver)
        } else {
            // Final step — destination
            let maneuver = CPManeuver()
            maneuver.instructionVariants = ["목적지에 도착합니다"]
            maneuver.symbolImage = UIImage(systemName: "flag.fill")

            let estimates = CPTravelEstimates(
                distanceRemaining: Measurement(
                    value: progress.distanceToNextManeuver,
                    unit: .meters
                ),
                timeRemaining: progress.timeRemaining
            )
            maneuver.initialTravelEstimates = estimates
            currentManeuvers.append(maneuver)
            upcomingManeuvers.append(maneuver)
        }

        // Add maneuvers to session (required before setting upcomingManeuvers)
        let newManeuvers = upcomingManeuvers.filter { maneuver in
            !addedManeuvers.contains(where: {
                $0.instructionVariants == maneuver.instructionVariants
            })
        }
        if !newManeuvers.isEmpty {
            session.add(newManeuvers)
            addedManeuvers.append(contentsOf: newManeuvers)
        }

        // Update upcoming maneuvers on session
        session.upcomingManeuvers = upcomingManeuvers

        // Trip-level travel estimates
        let tripEstimates = CPTravelEstimates(
            distanceRemaining: Measurement(
                value: progress.distanceRemaining,
                unit: .meters
            ),
            timeRemaining: progress.timeRemaining
        )

        // Maneuver-level travel estimates
        let maneuverEstimates = CPTravelEstimates(
            distanceRemaining: Measurement(
                value: progress.distanceToNextManeuver,
                unit: .meters
            ),
            timeRemaining: progress.distanceToNextManeuver / 13.9 // ~50 km/h estimate
        )

        // Create and send route information
        let routeInfo = CPRouteInformation(
            maneuvers: upcomingManeuvers,
            laneGuidances: [],
            currentManeuvers: currentManeuvers,
            currentLaneGuidance: CPLaneGuidance(),
            trip: tripEstimates,
            maneuverTravelEstimates: maneuverEstimates
        )

        session.resumeTrip(updatedRouteInformation: routeInfo)
    }

    // MARK: - Maneuver Builder

    private func buildManeuver(from step: MKRoute.Step, distance: CLLocationDistance) -> CPManeuver {
        let maneuver = CPManeuver()

        let instruction = GuidanceTextBuilder.buildInstructionFromStep(step)
        maneuver.instructionVariants = [instruction]

        let iconName = GuidanceTextBuilder.iconNameForInstruction(instruction)
        maneuver.symbolImage = UIImage(systemName: iconName)

        let estimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: distance, unit: .meters),
            timeRemaining: distance / 13.9 // ~50 km/h default speed estimate
        )
        maneuver.initialTravelEstimates = estimates

        return maneuver
    }
}
