import UIKit
import CarPlay
import CoreLocation
import Combine

/// CarPlay 주행 안내 — NavigationGuide를 구독하여 CPManeuver/CPRouteInformation 갱신
final class CarPlayNavigationHandler {

    // MARK: - Properties

    private var navigationSession: CPNavigationSession?
    private var cancellables = Set<AnyCancellable>()
    private var addedManeuvers: [CPManeuver] = []

    // MARK: - Start

    func startNavigation(
        trip: CPTrip,
        mapTemplate: CPMapTemplate,
        guidePublisher: CurrentValueSubject<NavigationGuide?, Never>
    ) {
        stopNavigation()

        let session = mapTemplate.startNavigationSession(for: trip)
        session.pauseTrip(for: .loading, description: "경로 준비 중", turnCardColor: nil)
        self.navigationSession = session

        // guidePublisher 구독
        guidePublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] guide in
                self?.handleGuide(guide, session: session)
            }
            .store(in: &cancellables)
    }

    // MARK: - Stop

    func stopNavigation() {
        cancellables.removeAll()
        navigationSession?.finishTrip()
        navigationSession = nil
        addedManeuvers = []
    }

    // MARK: - Handle Guide

    private func handleGuide(_ guide: NavigationGuide, session: CPNavigationSession) {
        // 상태 처리
        handleState(guide.state, session: session)

        guard guide.state == .navigating else { return }

        // Maneuver 생성
        var currentManeuvers: [CPManeuver] = []
        var upcomingManeuvers: [CPManeuver] = []

        if let maneuver = guide.currentManeuver {
            let cpManeuver = buildManeuver(
                instruction: maneuver.instruction,
                turnType: maneuver.turnType,
                distance: maneuver.distance
            )
            currentManeuvers.append(cpManeuver)
            upcomingManeuvers.append(cpManeuver)
        }

        if let next = guide.nextManeuver {
            let cpManeuver = buildManeuver(
                instruction: next.instruction,
                turnType: next.turnType,
                distance: next.distance
            )
            upcomingManeuvers.append(cpManeuver)
        }

        // 새 maneuver 등록
        let newManeuvers = upcomingManeuvers.filter { maneuver in
            !addedManeuvers.contains(where: {
                $0.instructionVariants == maneuver.instructionVariants
            })
        }
        if !newManeuvers.isEmpty {
            session.add(newManeuvers)
            addedManeuvers.append(contentsOf: newManeuvers)
        }

        session.upcomingManeuvers = upcomingManeuvers

        // Trip-level travel estimates
        let tripEstimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: guide.remainingDistance, unit: .meters),
            timeRemaining: guide.remainingTime
        )

        // Maneuver-level travel estimates
        let maneuverDistance = guide.currentManeuver?.distance ?? 0
        let maneuverEstimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: maneuverDistance, unit: .meters),
            timeRemaining: maneuverDistance / max(guide.speed, 5.0)
        )

        // Route information 전송
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

    // MARK: - State

    private func handleState(_ state: NavigationState, session: CPNavigationSession) {
        switch state {
        case .rerouting:
            session.pauseTrip(for: .rerouting, description: "경로 재탐색 중", turnCardColor: nil)
        case .arrived:
            session.finishTrip()
            stopNavigation()
        case .stopped:
            session.cancelTrip()
            stopNavigation()
        case .navigating, .preparing:
            break
        }
    }

    // MARK: - Build Maneuver

    private func buildManeuver(
        instruction: String,
        turnType: TurnType,
        distance: CLLocationDistance
    ) -> CPManeuver {
        let maneuver = CPManeuver()
        maneuver.instructionVariants = [instruction]
        maneuver.symbolImage = UIImage(systemName: turnType.iconName)

        let estimates = CPTravelEstimates(
            distanceRemaining: Measurement(value: distance, unit: .meters),
            timeRemaining: distance / 13.9  // ~50km/h 기본 추정
        )
        maneuver.initialTravelEstimates = estimates

        return maneuver
    }
}
