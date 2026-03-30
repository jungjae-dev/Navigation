import CoreLocation
import Combine

/// 네비게이션 주행 엔진 (조합기)
/// GPS → 맵매칭 → 경로 추적 → 상태 관리 → 음성 트리거 → NavigationGuide 발행
final class NavigationEngine {

    // MARK: - Output

    let guidePublisher = CurrentValueSubject<NavigationGuide?, Never>(nil)

    // MARK: - Components

    private var mapMatcher: MapMatcher
    private var routeTracker: RouteTracker
    private let offRouteDetector: OffRouteDetector
    private let stateManager: StateManager
    private var voiceEngine: VoiceEngine
    private var deadReckoning: DeadReckoning

    // MARK: - Configuration

    private var route: Route
    private let transportMode: TransportMode
    private let routeService: RouteProviding
    private let logger = NavigationLogger.shared

    // MARK: - Reroute State

    private var isRerouteInProgress = false
    private var rerouteAttempts = 0
    private let maxRerouteAttempts = 3
    private let rerouteRetryInterval: TimeInterval = 10
    private var rerouteTask: Task<Void, Never>?

    // MARK: - Init

    init(
        route: Route,
        transportMode: TransportMode,
        routeService: RouteProviding
    ) {
        self.route = route
        self.transportMode = transportMode
        self.routeService = routeService

        self.mapMatcher = MapMatcher(polyline: route.polylineCoordinates, transportMode: transportMode)
        self.routeTracker = RouteTracker(route: route)
        self.offRouteDetector = OffRouteDetector()
        self.stateManager = StateManager()
        self.voiceEngine = VoiceEngine(provider: route.provider)
        self.deadReckoning = DeadReckoning(polyline: route.polylineCoordinates)

        setupCallbacks()
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        routeTracker.onStepAdvance = { [weak self] from, to, instruction in
            self?.logger.logStepAdvance(from: from, to: to, instruction: instruction)
            self?.voiceEngine.onStepAdvanced(previousStepIndex: from)
        }

        stateManager.onStateChange = { [weak self] from, to in
            self?.logger.logStateChange(from: from, to: to)
        }
    }

    // MARK: - Tick (매 1초)

    /// GPSProvider로부터 1초마다 호출
    func tick(gps: GPSData) {
        logger.logGPS(gps)

        var matchedPosition: CLLocationCoordinate2D
        var heading: CLLocationDirection
        var isOffRoute = false

        if gps.isValid {
            // GPS valid → 맵매칭 + 이탈 감지
            let matchResult = mapMatcher.match(gps)
            logger.logMatch(matchResult)

            if matchResult.isMatched {
                deadReckoning.updateLastValid(
                    position: matchResult.coordinate,
                    speed: gps.speed,
                    segmentIndex: matchResult.segmentIndex
                )
            }

            isOffRoute = offRouteDetector.update(matchResult: matchResult, gpsAccuracy: gps.accuracy)
            logger.logOffRoute(consecutiveFailures: offRouteDetector.consecutiveFailures, isOffRoute: isOffRoute)

            matchedPosition = matchResult.coordinate
            heading = matchResult.isMatched
                ? bearingAtSegment(matchResult.segmentIndex)
                : gps.heading

            logger.logDeadReckoning(active: false)
        } else {
            // GPS invalid → Dead Reckoning (맵매칭/이탈감지 스킵)
            if let drResult = deadReckoning.estimate(currentTime: gps.timestamp) {
                matchedPosition = drResult.coordinate
                heading = drResult.heading
                logger.logDeadReckoning(active: true, estimatedDistance: gps.speed * 1.0)
            } else {
                matchedPosition = gps.coordinate
                heading = gps.heading
                logger.logDeadReckoning(active: false)
            }
        }

        // segmentIndex 결정 (경로 추적에 전달)
        let currentSegmentIndex: Int
        if gps.isValid {
            currentSegmentIndex = mapMatcher.currentSegmentIndex
        } else {
            // GPS invalid: DR 추정 위치의 segmentIndex 사용
            if let drResult = deadReckoning.estimate(currentTime: gps.timestamp) {
                currentSegmentIndex = drResult.segmentIndex
            } else {
                currentSegmentIndex = mapMatcher.currentSegmentIndex
            }
        }

        let routeProgress = routeTracker.update(
            matchedPosition: matchedPosition,
            segmentIndex: currentSegmentIndex
        )

        logger.logTrackProgress(
            stepIndex: routeProgress.currentStepIndex,
            totalSteps: routeProgress.totalSteps,
            distanceToManeuver: routeProgress.distanceToNextManeuver,
            remainingDistance: routeProgress.remainingDistance,
            eta: routeProgress.eta
        )

        // 상태 관리
        let state = stateManager.update(
            isMatched: gps.isValid ? mapMatcher.currentSegmentIndex >= 0 : true,
            isOffRoute: isOffRoute,
            distanceToGoal: routeProgress.remainingDistance
        )

        // 이탈 확정 시 자동 재탐색
        if isOffRoute && !isRerouteInProgress {
            startReroute(from: gps.coordinate)
        }

        // 음성 트리거
        var voiceCommand: VoiceCommand?

        // 초기 안내 (preparing → navigating 전환 시)
        if state == .navigating {
            voiceCommand = voiceEngine.checkInitial()
        }

        // 일반 음성 안내
        if voiceCommand == nil && state == .navigating {
            voiceCommand = voiceEngine.check(
                distanceToManeuver: routeProgress.distanceToNextManeuver,
                speed: gps.speed,
                stepIndex: routeProgress.currentStepIndex,
                step: routeProgress.currentStep
            )
        }

        // 도착 음성
        if state == .arrived && voiceCommand == nil {
            voiceCommand = VoiceCommand(text: "목적지에 도착했습니다", priority: .urgent)
        }

        // 재탐색 음성
        if isOffRoute && state == .rerouting {
            voiceCommand = VoiceCommand(text: "경로를 재탐색합니다", priority: .urgent)
        }

        if let vc = voiceCommand {
            logger.logVoiceTrigger(
                stepIndex: routeProgress.currentStepIndex,
                distance: routeProgress.distanceToNextManeuver,
                text: vc.text
            )
        }

        // NavigationGuide 조립
        let guide = NavigationGuide(
            state: state,
            currentManeuver: makeManeuverInfo(from: routeProgress.currentStep, distance: routeProgress.distanceToNextManeuver),
            nextManeuver: routeProgress.nextStep.map { makeManeuverInfo(from: $0, distance: $0.distance) },
            remainingDistance: routeProgress.remainingDistance,
            remainingTime: routeProgress.remainingTime,
            eta: routeProgress.eta,
            matchedPosition: matchedPosition,
            heading: heading,
            speed: gps.speed,
            isGPSValid: gps.isValid,
            voiceCommand: voiceCommand
        )

        guidePublisher.send(guide)
    }

    // MARK: - Configure

    /// 출발 좌표 설정 (OffRouteDetector 보호 조건용)
    func setStartCoordinate(_ coordinate: CLLocationCoordinate2D) {
        offRouteDetector.start(at: coordinate)
    }

    // MARK: - Stop

    func stop() {
        rerouteTask?.cancel()
        rerouteTask = nil
        stateManager.stop()
    }

    // MARK: - Reroute

    /// 수동 재탐색 요청
    func requestReroute(from coordinate: CLLocationCoordinate2D) {
        stateManager.requestReroute()
        startReroute(from: coordinate)
    }

    private func startReroute(from coordinate: CLLocationCoordinate2D) {
        guard !isRerouteInProgress else { return }
        isRerouteInProgress = true
        rerouteAttempts = 0

        rerouteTask = Task { [weak self] in
            await self?.executeReroute(from: coordinate)
        }
    }

    private func executeReroute(from coordinate: CLLocationCoordinate2D) async {
        guard let destination = route.polylineCoordinates.last else {
            stateManager.rerouteFailed()
            isRerouteInProgress = false
            return
        }

        while rerouteAttempts < maxRerouteAttempts {
            rerouteAttempts += 1

            do {
                let routes = try await routeService.calculateRoutes(
                    from: coordinate,
                    to: destination,
                    transportMode: transportMode
                )

                guard let newRoute = routes.first else {
                    throw LBSError.noRoutesFound
                }

                // 엔진 컴포넌트 리셋
                await MainActor.run { [weak self] in
                    self?.applyNewRoute(newRoute)
                }
                return

            } catch {
                if rerouteAttempts < maxRerouteAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(rerouteRetryInterval * 1_000_000_000))
                }
            }
        }

        // 3회 모두 실패
        await MainActor.run { [weak self] in
            self?.stateManager.rerouteFailed()
            self?.offRouteDetector.reset()
            self?.isRerouteInProgress = false
        }
    }

    private func applyNewRoute(_ newRoute: Route) {
        route = newRoute
        mapMatcher = MapMatcher(polyline: newRoute.polylineCoordinates, transportMode: transportMode)
        routeTracker = RouteTracker(route: newRoute)
        voiceEngine = VoiceEngine(provider: newRoute.provider)
        deadReckoning = DeadReckoning(polyline: newRoute.polylineCoordinates)
        offRouteDetector.reset()
        setupCallbacks()

        stateManager.rerouteSucceeded()
        isRerouteInProgress = false

        logger.logRouteConverted(provider: newRoute.provider, stepCount: newRoute.steps.count, polylineCount: newRoute.polylineCoordinates.count)
    }

    // MARK: - Helpers

    private func makeManeuverInfo(from step: RouteStep, distance: CLLocationDistance) -> ManeuverInfo {
        ManeuverInfo(
            instruction: step.instructions,
            distance: distance,
            turnType: step.turnType,
            roadName: step.roadName
        )
    }

    private func bearingAtSegment(_ segmentIndex: Int) -> CLLocationDirection {
        let coords = route.polylineCoordinates
        guard segmentIndex < coords.count - 1 else { return 0 }

        let from = coords[segmentIndex]
        let to = coords[segmentIndex + 1]

        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
