import CoreLocation
import Combine

/// 네비게이션 주행 엔진 (조합기)
/// GPS → 맵매칭 → 경로 추적 → 상태 관리 → 음성 트리거 → NavigationGuide 발행
final class NavigationEngine {

    // MARK: - Output

    let guidePublisher = CurrentValueSubject<NavigationGuide?, Never>(nil)

    /// 활성 경로 — reroute 시 send. 모든 route 의 단일 진실.
    let routePublisher: CurrentValueSubject<Route, Never>

    // MARK: - Components

    private var mapMatcher: MapMatcher
    private var routeTracker: RouteTracker
    private let offRouteDetector: OffRouteDetector
    private let stateManager: StateManager
    private var voiceEngine: VoiceEngine
    private var lastMatchedPosition: CLLocationCoordinate2D?

    // MARK: - Predictive Display

    /// 직전 GPS 속도 — min(lastSpeed, currentSpeed) 로 예측거리 보수화
    private var lastSpeed: CLLocationSpeed = 0

    // MARK: - Configuration

    private var route: Route { routePublisher.value }
    private let transportMode: TransportMode
    private let routeService: RouteProviding
    private let logger = NavigationLogger.shared

    // MARK: - Reroute State

    private var isRerouteInProgress = false
    private var rerouteAttempts = 0
    private let maxRerouteAttempts = 3
    private let rerouteRetryInterval: TimeInterval = 10
    private var rerouteTask: Task<Void, Never>?

    /// heading 신뢰 임계 속도 (m/s). 미만이면 GPS heading 무시.
    private let headingSpeedGate: CLLocationSpeed = 3.0
    /// 새 경로 첫 segment 와 user heading 의 허용 각도차 (절대값, 도)
    private let routeAlignmentTolerance: Double = 90

    // MARK: - Init

    init(
        route: Route,
        transportMode: TransportMode,
        routeService: RouteProviding
    ) {
        self.routePublisher = CurrentValueSubject<Route, Never>(route)
        self.transportMode = transportMode
        self.routeService = routeService

        self.mapMatcher = MapMatcher(polyline: route.polylineCoordinates, transportMode: transportMode)
        self.routeTracker = RouteTracker(route: route)
        self.offRouteDetector = OffRouteDetector()
        self.stateManager = StateManager()
        self.voiceEngine = VoiceEngine(provider: route.provider)

        logger.resetDisplayState()
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

    func tick(location: CLLocation) {
        logger.logGPS(location)

        let isGPSValid = location.isValid
        let speed = location.safeSpeed

        let matched = resolveMatchedState(location: location)
        let routeProgress = routeTracker.update(
            matchedPosition: matched.position,
            segmentIndex: mapMatcher.currentSegmentIndex
        )
        logger.logTrackProgress(
            stepIndex: routeProgress.currentStepIndex,
            totalSteps: routeProgress.totalSteps,
            distanceToManeuver: routeProgress.distanceToNextManeuver,
            remainingDistance: routeProgress.remainingDistance,
            eta: routeProgress.eta
        )

        let state = stateManager.update(
            isMatched: isGPSValid ? matched.isMatched : true,
            isOffRoute: matched.isOffRoute,
            distanceToGoal: routeProgress.remainingDistance
        )

        if matched.isOffRoute && !isRerouteInProgress {
            startReroute(
                from: location.coordinate,
                heading: makeRerouteHeading(gpsHeading: location.course, gpsSpeed: speed, fallback: matched.heading)
            )
        }

        let voiceCommand = resolveVoiceCommand(state: state, routeProgress: routeProgress, speed: speed)
        if let vc = voiceCommand {
            logger.logVoiceTrigger(
                stepIndex: routeProgress.currentStepIndex,
                distance: routeProgress.distanceToNextManeuver,
                text: vc.text
            )
        }

        logger.logDisplay(matchedPosition: matched.position, heading: matched.heading, isMatched: matched.isMatched, isGPSLoss: location.isGPSLoss)

        guidePublisher.send(NavigationGuide(
            state: state,
            currentManeuver: makeManeuverInfo(from: routeProgress.currentStep, distance: routeProgress.distanceToNextManeuver),
            nextManeuver: routeProgress.nextStep.map { makeManeuverInfo(from: $0, distance: $0.distance) },
            remainingDistance: routeProgress.remainingDistance,
            remainingTime: routeProgress.remainingTime,
            eta: routeProgress.eta,
            matchedPosition: matched.position,
            heading: matched.heading,
            speed: speed,
            rawGPSPosition: isGPSValid ? location.coordinate : nil,
            rawGPSHeading: isGPSValid ? location.course : nil,
            isMatched: matched.isMatched,
            isGPSValid: isGPSValid,
            voiceCommand: voiceCommand
        ))
    }

    // MARK: - Tick Helpers

    private struct MatchedState {
        let position: CLLocationCoordinate2D
        let heading: CLLocationDirection
        let isMatched: Bool
        let isOffRoute: Bool
    }

    private func resolveMatchedState(location: CLLocation) -> MatchedState {
        // 실제 GPS 또는 GPS 손실 신호(isGPSLoss) → 맵매칭 실행
        // accuracy < 0 인 완전 무효 GPS만 스킵
        guard location.isValid || location.isGPSLoss else {
            if let lastPos = lastMatchedPosition {
                return MatchedState(position: lastPos, heading: bearingAtSegment(mapMatcher.currentSegmentIndex), isMatched: false, isOffRoute: false)
            }
            return MatchedState(position: location.coordinate, heading: location.course, isMatched: false, isOffRoute: false)
        }

        let matchResult = mapMatcher.match(location)
        logger.logMatch(matchResult)
        let isOffRoute = offRouteDetector.update(matchResult: matchResult, gpsAccuracy: location.horizontalAccuracy)

        if matchResult.isMatched {
            lastMatchedPosition = matchResult.coordinate

            let predictSpeed = min(lastSpeed, location.safeSpeed)
            lastSpeed = location.safeSpeed

            let displayResult: MatchResult
            if predictSpeed > 0, DevToolsSettings.shared.predictiveDisplayEnabled.value {
                let bearing = bearingAtSegment(matchResult.segmentIndex)
                let g4prime = matchResult.coordinate.moved(distance: predictSpeed * 1.0, bearing: bearing)
                let g4Location = CLLocation(latitude: g4prime.latitude, longitude: g4prime.longitude)
                let g4Match = mapMatcher.match(g4Location)
                displayResult = g4Match.isMatched ? g4Match : matchResult
            } else {
                displayResult = matchResult
            }

            return MatchedState(
                position: displayResult.coordinate,
                heading: bearingAtSegment(displayResult.segmentIndex),
                isMatched: true,
                isOffRoute: isOffRoute
            )
        }
        if let lastPos = lastMatchedPosition {
            return MatchedState(position: lastPos, heading: bearingAtSegment(mapMatcher.currentSegmentIndex), isMatched: false, isOffRoute: isOffRoute)
        }
        return MatchedState(position: matchResult.coordinate, heading: location.course, isMatched: false, isOffRoute: isOffRoute)
    }

    private func resolveVoiceCommand(state: NavigationState, routeProgress: RouteProgress, speed: CLLocationSpeed) -> VoiceCommand? {
        if state == .navigating, let cmd = voiceEngine.checkInitial() { return cmd }
        if state == .navigating, let cmd = voiceEngine.check(
            distanceToManeuver: routeProgress.distanceToNextManeuver,
            speed: speed,
            stepIndex: routeProgress.currentStepIndex,
            step: routeProgress.currentStep
        ) { return cmd }
        return voiceEngine.checkStateChange(state: state)
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
    func requestReroute(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection? = nil) {
        stateManager.requestReroute()
        startReroute(from: coordinate, heading: heading)
    }

    private func startReroute(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection?) {
        guard !isRerouteInProgress else { return }
        isRerouteInProgress = true
        rerouteAttempts = 0
        lastMatchedPosition = nil

        logger.logRerouteStart(from: coordinate)

        rerouteTask = Task { [weak self] in
            await self?.executeReroute(from: coordinate, heading: heading)
        }
    }

    private func executeReroute(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection?) async {
        guard let destination = route.polylineCoordinates.last else {
            await MainActor.run { [weak self] in
                self?.stateManager.rerouteFailed()
                self?.isRerouteInProgress = false
            }
            return
        }

        while rerouteAttempts < maxRerouteAttempts {
            rerouteAttempts += 1
            logger.logRerouteAttempt(attempt: rerouteAttempts, maxAttempts: maxRerouteAttempts)

            do {
                let routes = try await routeService.calculateRoutes(
                    from: coordinate,
                    to: destination,
                    heading: heading,
                    transportMode: transportMode
                )

                guard let newRoute = routes.first else {
                    throw LBSError.noRoutesFound
                }

                // 진행방향 정렬 검증 — Kakao 만 적용
                // Kakao: angle 파라미터로 API 레벨 방향 강제 → 검증 의미 있음
                // Apple: lateral offset 은 best-effort (미분리 도로에서 실패 가능)
                //        → 검증 실패 시 무한 루프 유발하므로 스킵
                if newRoute.provider == .kakao,
                   let h = heading,
                   let firstBearing = MapGeometry.firstBearing(of: newRoute.polylineCoordinates) {
                    let delta = abs(MapGeometry.angleDelta(h, firstBearing))
                    if delta >= routeAlignmentTolerance {
                        logger.logRerouteMisaligned(routeBearing: firstBearing, userHeading: h, delta: delta)
                        throw LBSError.routeMisaligned
                    }
                }

                // 엔진 컴포넌트 리셋
                await MainActor.run { [weak self] in
                    self?.applyNewRoute(newRoute)
                }
                return

            } catch let lbsError as LBSError where lbsError == .routeMisaligned {
                // 방향 불일치 — 같은 heading 으로 재시도해봤자 동일 결과.
                // heading 없이 한 번만 즉시 재시도 후 포기 (대기 없음).
                logger.logRerouteFailure(error: lbsError, attempt: rerouteAttempts)
                if let fallbackRoutes = try? await routeService.calculateRoutes(
                    from: coordinate, to: destination, heading: nil, transportMode: transportMode
                ), let fallbackRoute = fallbackRoutes.first {
                    await MainActor.run { [weak self] in self?.applyNewRoute(fallbackRoute) }
                    return
                }
                break
            } catch {
                logger.logRerouteFailure(error: error, attempt: rerouteAttempts)
                if rerouteAttempts < maxRerouteAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(rerouteRetryInterval * 1_000_000_000))
                }
            }
        }

        // 3회 모두 실패 — 5초/35m 보호 재적용 (재탐색 직후 즉시 재이탈 차단)
        logger.logRerouteGiveUp(attempts: rerouteAttempts)
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.stateManager.rerouteFailed()
            self.offRouteDetector.start(at: coordinate)  // reset() 대신 start() — 보호 일관성 유지
            self.isRerouteInProgress = false
        }
    }

    private func applyNewRoute(_ newRoute: Route) {
        // 단일 mutation 지점 — publisher 발행 + 컴포넌트 재생성을 함께 수행
        routePublisher.send(newRoute)
        mapMatcher = MapMatcher(polyline: newRoute.polylineCoordinates, transportMode: transportMode)
        routeTracker = RouteTracker(route: newRoute)
        voiceEngine = VoiceEngine(provider: newRoute.provider)
        lastMatchedPosition = nil
        lastSpeed = 0

        // 재탐색 직후 출발 보호 재적용 (5초/35m 동안 재이탈 판정 보류)
        if let firstCoord = newRoute.polylineCoordinates.first {
            offRouteDetector.start(at: firstCoord)
        } else {
            offRouteDetector.reset()
        }
        setupCallbacks()

        stateManager.rerouteSucceeded()
        isRerouteInProgress = false

        logger.logRerouteSuccess(
            provider: newRoute.provider,
            stepCount: newRoute.steps.count,
            polylineCount: newRoute.polylineCoordinates.count
        )
    }

    /// GPS heading 의 신뢰성을 속도로 게이트하고, 부적합하면 fallback(매칭 segment bearing)을 사용
    private func makeRerouteHeading(
        gpsHeading: CLLocationDirection,
        gpsSpeed: CLLocationSpeed,
        fallback: CLLocationDirection
    ) -> CLLocationDirection? {
        if gpsSpeed >= headingSpeedGate, gpsHeading.isFinite, gpsHeading >= 0 {
            return gpsHeading
        }
        if fallback.isFinite, fallback >= 0 {
            return fallback
        }
        return nil
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
        return MapGeometry.bearing(from: coords[segmentIndex], to: coords[segmentIndex + 1])
    }

}
