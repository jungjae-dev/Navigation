import Foundation
import Combine
import CoreLocation

// MARK: - Navigation Session

struct NavigationSession {
    let destination: Place
    let engine: NavigationEngine
    // route 는 engine 의 routePublisher 에 위임 (reroute 시 자동 반영, stale snapshot 차단)
    var route: Route { engine.routePublisher.value }
    // GPS provider lifecycle은 외부(AppCoordinator)에서 관리:
    // - Real/File: LocationService.setProvider/clearProvider
    // - 가상주행: VirtualDriveDriver.start/stop
}

// MARK: - Navigation Command

enum NavigationSource {
    case phone
    case carPlay
}

enum NavigationCommand {
    case started(source: NavigationSource)
    case stopped
}

// MARK: - NavigationSessionManager

final class NavigationSessionManager {

    static let shared = NavigationSessionManager()

    // MARK: - Publishers

    let guidePublisher = CurrentValueSubject<NavigationGuide?, Never>(nil)
    /// 활성 경로 — 세션 종료 시 nil. reroute 시 새 Route 발행.
    let routePublisher = CurrentValueSubject<Route?, Never>(nil)
    let navigationCommandPublisher = PassthroughSubject<NavigationCommand, Never>()

    // MARK: - Session

    private(set) var activeSession: NavigationSession?

    var isNavigating: Bool {
        activeSession != nil
    }

    // MARK: - Dependencies

    private let locationService = LocationService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {}

    // MARK: - Start Navigation

    func startNavigation(
        route: Route,
        destination: Place,
        transportMode: TransportMode,
        locationPublisher: AnyPublisher<CLLocation, Never>,
        source: NavigationSource
    ) {
        // 기존 세션 정리
        if isNavigating {
            stopNavigation()
        }

        // 엔진 생성
        let engine = NavigationEngine(
            route: route,
            transportMode: transportMode,
            routeService: LBSServiceProvider.shared.route
        )

        // GPS → 엔진 연결 (publisher 구독만, lifecycle은 외부 관리)
        locationPublisher
            .sink { [weak engine] location in
                engine?.tick(location: location)
            }
            .store(in: &cancellables)

        // 엔진 출력 → 외부 전달 (guide + route 동일 패턴)
        engine.guidePublisher
            .sink { [weak self] guide in
                self?.guidePublisher.send(guide)
            }
            .store(in: &cancellables)

        engine.routePublisher
            .sink { [weak self] route in
                self?.routePublisher.send(route)
            }
            .store(in: &cancellables)

        // 세션 저장
        let session = NavigationSession(
            destination: destination,
            engine: engine
        )
        activeSession = session

        // 위치 서비스 네비게이션 모드
        if transportMode == .walking {
            locationService.configureForWalking()
        } else {
            locationService.configureForNavigation()
        }

        // 출발 좌표 설정 (OffRouteDetector 보호 조건용)
        if let currentLocation = locationService.bestAvailableLocation {
            engine.setStartCoordinate(currentLocation.coordinate)
        }

        // 명령 발행
        navigationCommandPublisher.send(.started(source: source))
    }

    // MARK: - Stop Navigation

    func stopNavigation() {
        guard let session = activeSession else { return }

        session.engine.stop()

        cancellables.removeAll()
        locationService.configureForStandard()

        activeSession = nil
        guidePublisher.send(nil)
        routePublisher.send(nil)
        navigationCommandPublisher.send(.stopped)
    }

    // MARK: - Reroute

    func requestReroute() {
        guard let session = activeSession,
              let location = locationService.bestAvailableLocation else { return }
        session.engine.requestReroute(from: location.coordinate)
    }
}
