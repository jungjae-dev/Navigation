import Foundation
import Combine
import CoreLocation

// MARK: - Navigation Session

struct NavigationSession {
    let route: Route
    let destination: Place
    let engine: NavigationEngine
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
        gpsPublisher: AnyPublisher<GPSData, Never>,
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
        gpsPublisher
            .sink { [weak engine] gps in
                engine?.tick(gps: gps)
            }
            .store(in: &cancellables)

        // 엔진 출력 → 외부 전달
        engine.guidePublisher
            .sink { [weak self] guide in
                self?.guidePublisher.send(guide)
            }
            .store(in: &cancellables)

        // 세션 저장
        let session = NavigationSession(
            route: route,
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
        navigationCommandPublisher.send(.stopped)
    }

    // MARK: - Reroute

    func requestReroute() {
        guard let session = activeSession,
              let location = locationService.bestAvailableLocation else { return }
        session.engine.requestReroute(from: location.coordinate)
    }
}
