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
    private var deadReckoning: DeadReckoning

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
        var isMatched = false

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
            isMatched = matchResult.isMatched

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
            let rerouteHeading = makeRerouteHeading(gpsHeading: gps.heading, gpsSpeed: gps.speed, fallback: heading)
            startReroute(from: gps.coordinate, heading: rerouteHeading)
        }

        // 음성 트리거 (모든 음성은 VoiceEngine에서 관리)
        var voiceCommand: VoiceCommand?

        // 초기 안내 (preparing → navigating 전환 시)
        if state == .navigating {
            voiceCommand = voiceEngine.checkInitial()
        }

        // 거리별 안내
        if voiceCommand == nil && state == .navigating {
            voiceCommand = voiceEngine.check(
                distanceToManeuver: routeProgress.distanceToNextManeuver,
                speed: gps.speed,
                stepIndex: routeProgress.currentStepIndex,
                step: routeProgress.currentStep
            )
        }

        // 상태 변화 안내 (도착/재탐색 — 각 1회)
        if voiceCommand == nil {
            voiceCommand = voiceEngine.checkStateChange(state: state)
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
            rawGPSPosition: gps.isValid ? gps.coordinate : nil,
            rawGPSHeading: gps.isValid ? gps.heading : nil,
            isMatched: isMatched,
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
    func requestReroute(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection? = nil) {
        stateManager.requestReroute()
        startReroute(from: coordinate, heading: heading)
    }

    private func startReroute(from coordinate: CLLocationCoordinate2D, heading: CLLocationDirection?) {
        guard !isRerouteInProgress else { return }
        isRerouteInProgress = true
        rerouteAttempts = 0

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

                // 진행방향 정렬 검증 — heading 이 있고, 첫 segment bearing 과 90° 이상 어긋나면 거부
                if let h = heading,
                   let firstBearing = Self.firstBearing(of: newRoute.polylineCoordinates) {
                    let delta = abs(Self.angleDelta(h, firstBearing))
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

        // 3회 모두 실패
        logger.logRerouteGiveUp(attempts: rerouteAttempts)
        await MainActor.run { [weak self] in
            self?.stateManager.rerouteFailed()
            self?.offRouteDetector.reset()
            self?.isRerouteInProgress = false
        }
    }

    private func applyNewRoute(_ newRoute: Route) {
        // 단일 mutation 지점 — publisher 발행 + 컴포넌트 재생성을 함께 수행
        routePublisher.send(newRoute)
        mapMatcher = MapMatcher(polyline: newRoute.polylineCoordinates, transportMode: transportMode)
        routeTracker = RouteTracker(route: newRoute)
        voiceEngine = VoiceEngine(provider: newRoute.provider)
        deadReckoning = DeadReckoning(polyline: newRoute.polylineCoordinates)

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

    static func firstBearing(of polyline: [CLLocationCoordinate2D]) -> CLLocationDirection? {
        MapGeometry.firstBearing(of: polyline)
    }

    static func angleDelta(_ a: CLLocationDirection, _ b: CLLocationDirection) -> Double {
        MapGeometry.angleDelta(a, b)
    }
}
