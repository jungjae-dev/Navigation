import Testing
import Combine
import CoreLocation
@testable import Navigation

struct NavigationSessionManagerTests {

    // MARK: - Helpers

    private var sessionManager: NavigationSessionManager {
        NavigationSessionManager.shared
    }

    private func makeRoute() -> Route {
        TestFixtures.sampleRoute
    }

    private func makeDestination() -> Place {
        TestFixtures.samplePlace
    }

    private func makeGPSPublisher() -> AnyPublisher<GPSData, Never> {
        // 테스트용 — 좌표 발행은 하지 않고 sessionManager가 구독 처리만 검증
        Empty<GPSData, Never>(completeImmediately: false).eraseToAnyPublisher()
    }

    // MARK: - Tests

    @Test func initialStateIsNotNavigating() {
        sessionManager.stopNavigation()

        #expect(!sessionManager.isNavigating)
        #expect(sessionManager.activeSession == nil)
    }

    @Test func startNavigationCreatesSession() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            transportMode: .automobile,
            gpsPublisher: makeGPSPublisher(),
            source: .phone
        )

        #expect(sessionManager.isNavigating)
        #expect(sessionManager.activeSession != nil)

        sessionManager.stopNavigation()
    }

    @Test func stopNavigationClearsSession() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            transportMode: .automobile,
            gpsPublisher: makeGPSPublisher(),
            source: .phone
        )

        sessionManager.stopNavigation()

        #expect(!sessionManager.isNavigating)
        #expect(sessionManager.activeSession == nil)
    }

    @Test func commandPublisherEmitsStarted() {
        var receivedCommand: NavigationCommand?
        var cancellables = Set<AnyCancellable>()

        sessionManager.navigationCommandPublisher
            .sink { command in
                receivedCommand = command
            }
            .store(in: &cancellables)

        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            transportMode: .automobile,
            gpsPublisher: makeGPSPublisher(),
            source: .carPlay
        )

        if case .started(let source) = receivedCommand {
            #expect(source == .carPlay)
        } else {
            Issue.record("Expected .started command")
        }

        sessionManager.stopNavigation()
        cancellables.removeAll()
    }

    @Test func commandPublisherEmitsStopped() {
        var receivedCommand: NavigationCommand?
        var cancellables = Set<AnyCancellable>()

        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            transportMode: .automobile,
            gpsPublisher: makeGPSPublisher(),
            source: .phone
        )

        sessionManager.navigationCommandPublisher
            .sink { command in
                receivedCommand = command
            }
            .store(in: &cancellables)

        sessionManager.stopNavigation()

        if case .stopped = receivedCommand {
            // OK
        } else {
            Issue.record("Expected .stopped command")
        }

        cancellables.removeAll()
    }

    @Test func stopWhenNotNavigatingIsNoOp() {
        sessionManager.stopNavigation()
        sessionManager.stopNavigation()
        #expect(!sessionManager.isNavigating)
    }
}
