import Foundation
import Combine
import MapKit
import CoreLocation

// MARK: - Models

enum NavigationState: Sendable {
    case preparing
    case navigating
    case rerouting
    case arrived
    case stopped
}

struct RouteProgress {
    let currentStepIndex: Int
    let totalSteps: Int
    let distanceToNextManeuver: CLLocationDistance
    let distanceRemaining: CLLocationDistance
    let timeRemaining: TimeInterval
    let estimatedArrivalTime: Date
    let currentStep: MKRoute.Step
    let nextStep: MKRoute.Step?
}

// MARK: - GuidanceEngine

final class GuidanceEngine {

    // MARK: - Publishers

    let navigationStatePublisher = CurrentValueSubject<NavigationState, Never>(.stopped)
    let routeProgressPublisher = CurrentValueSubject<RouteProgress?, Never>(nil)
    let currentStepPublisher = CurrentValueSubject<MKRoute.Step?, Never>(nil)
    let currentRoutePublisher = CurrentValueSubject<MKRoute?, Never>(nil)

    // MARK: - Dependencies

    private let locationService: LocationService
    private let routeService: RouteService
    private let voiceService: VoiceGuidanceService
    private let offRouteDetector: OffRouteDetector

    // MARK: - State

    private var route: MKRoute?
    private var steps: [MKRoute.Step] = []
    private var currentStepIndex = 0
    private var announcedThresholds: Set<Int> = []
    private var cancellables = Set<AnyCancellable>()
    private var rerouteDebounceDate: Date?
    private var transportMode: TransportMode = .automobile
    private var destination: CLLocationCoordinate2D?

    // MARK: - Configuration

    private let stepPassageThreshold: CLLocationDistance = 30.0
    private let arrivalThreshold: CLLocationDistance = 30.0
    private let rerouteDebounceInterval: TimeInterval = 10.0

    // MARK: - Init

    init(
        locationService: LocationService,
        routeService: RouteService,
        voiceService: VoiceGuidanceService,
        offRouteDetector: OffRouteDetector
    ) {
        self.locationService = locationService
        self.routeService = routeService
        self.voiceService = voiceService
        self.offRouteDetector = offRouteDetector
    }

    // MARK: - Public

    func startNavigation(with route: MKRoute, transportMode: TransportMode = .automobile) {
        self.route = route
        self.steps = route.steps
        self.currentStepIndex = 0
        self.announcedThresholds = []
        self.transportMode = transportMode
        self.rerouteDebounceDate = nil

        // Get destination coordinate from last step
        if let lastStep = steps.last {
            let polyline = lastStep.polyline
            let coords = polyline.coordinates
            destination = coords.last
        }

        offRouteDetector.configure(with: route)
        currentRoutePublisher.send(route)
        navigationStatePublisher.send(.navigating)

        if let firstStep = steps.first {
            currentStepPublisher.send(firstStep)
        }

        subscribeToLocation()

        // Initial voice guidance
        if steps.count > 1 {
            let nextStep = steps[1]
            let distance = Int(nextStep.distance)
            let text = GuidanceTextBuilder.buildText(
                for: .straightAhead(distance: distance)
            )
            voiceService.speak(text)
        }
    }

    func stopNavigation() {
        cancellables.removeAll()
        navigationStatePublisher.send(.stopped)
        routeProgressPublisher.send(nil)
        currentStepPublisher.send(nil)
        currentRoutePublisher.send(nil)
        voiceService.stop()
        offRouteDetector.reset()
        route = nil
        steps = []
    }

    // MARK: - Private: Location Subscription

    private func subscribeToLocation() {
        locationService.locationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    // MARK: - Core Logic

    private func handleLocationUpdate(_ location: CLLocation) {
        guard navigationStatePublisher.value == .navigating,
              let route = route else { return }

        // 1. Check arrival
        if checkArrival(location: location) {
            return
        }

        // 2. Check off-route
        let isOffRoute = offRouteDetector.checkLocation(location)
        if isOffRoute {
            handleOffRoute(from: location)
            return
        }

        // 3. Update step progress
        updateStepProgress(location: location)

        // 4. Calculate and publish progress
        let progress = calculateProgress(location: location, route: route)
        routeProgressPublisher.send(progress)
    }

    // MARK: - Step Tracking

    private func updateStepProgress(location: CLLocation) {
        guard currentStepIndex < steps.count else { return }

        let currentStep = steps[currentStepIndex]

        // Calculate distance to end of current step
        let stepEndCoord = stepEndCoordinate(for: currentStep)
        let distanceToStepEnd = DistanceCalculator.distance(
            from: location.coordinate,
            to: stepEndCoord
        )

        // Check if we've passed the current step
        if distanceToStepEnd < stepPassageThreshold && currentStepIndex < steps.count - 1 {
            advanceToNextStep()
            return
        }

        // Calculate distance to next maneuver (the step after current)
        let distanceToNext: CLLocationDistance
        if currentStepIndex + 1 < steps.count {
            let nextManeuverCoord = stepStartCoordinate(for: steps[currentStepIndex + 1])
            distanceToNext = DistanceCalculator.distance(
                from: location.coordinate,
                to: nextManeuverCoord
            )
        } else {
            distanceToNext = distanceToStepEnd
        }

        // Check and announce based on distance thresholds
        if currentStepIndex + 1 < steps.count {
            checkAndAnnounce(
                distance: distanceToNext,
                step: steps[currentStepIndex + 1],
                speed: location.speed
            )
        }
    }

    private func advanceToNextStep() {
        currentStepIndex += 1
        announcedThresholds.removeAll()

        guard currentStepIndex < steps.count else { return }

        let step = steps[currentStepIndex]
        currentStepPublisher.send(step)
    }

    // MARK: - Voice Announcement

    private func checkAndAnnounce(distance: CLLocationDistance, step: MKRoute.Step, speed: CLLocationSpeed) {
        let thresholds = announcementThresholds(for: speed)

        for threshold in thresholds {
            let thresholdInt = Int(threshold)

            // Skip already announced thresholds
            guard !announcedThresholds.contains(thresholdInt) else { continue }

            // Check if we're within the threshold range (±20% tolerance)
            let lowerBound = threshold * 0.8
            let upperBound = threshold * 1.2

            if distance >= lowerBound && distance <= upperBound {
                announcedThresholds.insert(thresholdInt)

                let instruction = step.instructions
                let text: String

                if threshold <= 50 {
                    text = GuidanceTextBuilder.buildText(for: .imminent(instruction: instruction))
                } else {
                    text = GuidanceTextBuilder.buildText(
                        for: .approaching(distance: Int(threshold), instruction: instruction)
                    )
                }

                voiceService.speak(text)
                break // Only announce one threshold per update
            }
        }
    }

    private func announcementThresholds(for speed: CLLocationSpeed) -> [CLLocationDistance] {
        switch transportMode {
        case .walking:
            return [200, 100, 50, 20]
        case .automobile:
            if speed > 22 { // > 80 km/h (highway)
                return [1000, 500, 200, 50]
            } else {
                return [500, 300, 100, 30]
            }
        }
    }

    // MARK: - Arrival Check

    private func checkArrival(location: CLLocation) -> Bool {
        guard let dest = destination else { return false }

        let distance = DistanceCalculator.distance(from: location.coordinate, to: dest)

        if distance < arrivalThreshold {
            navigationStatePublisher.send(.arrived)

            let text = GuidanceTextBuilder.buildText(for: .arrived)
            voiceService.speak(text)

            return true
        }

        return false
    }

    // MARK: - Off-Route Handling

    private func handleOffRoute(from location: CLLocation) {
        // Check debounce
        if let lastReroute = rerouteDebounceDate,
           Date().timeIntervalSince(lastReroute) < rerouteDebounceInterval {
            return
        }

        rerouteDebounceDate = Date()
        navigationStatePublisher.send(.rerouting)

        let text = GuidanceTextBuilder.buildText(for: .rerouting)
        voiceService.speak(text)

        Task { [weak self] in
            await self?.performReroute(from: location)
        }
    }

    private func performReroute(from location: CLLocation) async {
        guard let dest = destination else { return }

        do {
            let newRoutes = try await routeService.calculateRoutes(
                from: location.coordinate,
                to: dest,
                transportType: transportMode.mkTransportType
            )

            guard let newRoute = newRoutes.first else {
                navigationStatePublisher.send(.navigating)
                return
            }

            // Apply new route
            route = newRoute
            steps = newRoute.steps
            currentStepIndex = 0
            announcedThresholds = []

            offRouteDetector.configure(with: newRoute)
            currentRoutePublisher.send(newRoute)
            navigationStatePublisher.send(.navigating)

            if let firstStep = steps.first {
                currentStepPublisher.send(firstStep)
            }

            let text = GuidanceTextBuilder.buildText(for: .rerouted)
            voiceService.speak(text)

        } catch {
            // Reroute failed — continue with current route
            navigationStatePublisher.send(.navigating)
        }
    }

    // MARK: - Progress Calculation

    private func calculateProgress(location: CLLocation, route: MKRoute) -> RouteProgress {
        let currentStep = currentStepIndex < steps.count ? steps[currentStepIndex] : steps.last!

        // Distance to next maneuver
        let distanceToNext: CLLocationDistance
        if currentStepIndex + 1 < steps.count {
            let nextCoord = stepStartCoordinate(for: steps[currentStepIndex + 1])
            distanceToNext = DistanceCalculator.distance(from: location.coordinate, to: nextCoord)
        } else if let dest = destination {
            distanceToNext = DistanceCalculator.distance(from: location.coordinate, to: dest)
        } else {
            distanceToNext = 0
        }

        // Remaining distance (sum of remaining steps)
        var distanceRemaining = distanceToNext
        for i in (currentStepIndex + 1)..<steps.count {
            distanceRemaining += steps[i].distance
        }

        // Remaining time estimate
        let averageSpeed = max(location.speed, 10.0) // minimum 10 m/s for estimate
        let timeRemaining = distanceRemaining / averageSpeed

        let eta = Date().addingTimeInterval(timeRemaining)

        let nextStep = (currentStepIndex + 1 < steps.count) ? steps[currentStepIndex + 1] : nil

        return RouteProgress(
            currentStepIndex: currentStepIndex,
            totalSteps: steps.count,
            distanceToNextManeuver: distanceToNext,
            distanceRemaining: distanceRemaining,
            timeRemaining: timeRemaining,
            estimatedArrivalTime: eta,
            currentStep: currentStep,
            nextStep: nextStep
        )
    }

    // MARK: - Step Coordinate Helpers

    private func stepEndCoordinate(for step: MKRoute.Step) -> CLLocationCoordinate2D {
        let coords = step.polyline.coordinates
        return coords.last ?? CLLocationCoordinate2D()
    }

    private func stepStartCoordinate(for step: MKRoute.Step) -> CLLocationCoordinate2D {
        let coords = step.polyline.coordinates
        return coords.first ?? CLLocationCoordinate2D()
    }
}
