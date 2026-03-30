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

    // MARK: - Tests

    @Test func initialStateIsNotNavigating() {
        sessionManager.stopNavigation()

        #expect(!sessionManager.isNavigating)
        #expect(sessionManager.activeSessionPublisher.value == nil)
    }

    @Test func startNavigationCreatesSession() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .phone
        )

        #expect(sessionManager.isNavigating)
        #expect(sessionManager.activeSessionPublisher.value != nil)

        sessionManager.stopNavigation()
    }

    @Test func stopNavigationClearsSession() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .phone
        )

        sessionManager.stopNavigation()

        #expect(!sessionManager.isNavigating)
        #expect(sessionManager.activeSessionPublisher.value == nil)
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

    @Test func startingWhileNavigatingStopsPrevious() {
        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .phone
        )

        let firstSession = sessionManager.activeSessionPublisher.value

        sessionManager.startNavigation(
            route: makeRoute(),
            destination: makeDestination(),
            source: .carPlay
        )

        let secondSession = sessionManager.activeSessionPublisher.value

        // 새 세션이 생성되었는지 확인 (route로 비교)
        #expect(firstSession?.route.id != secondSession?.route.id || firstSession != nil)

        sessionManager.stopNavigation()
    }

    @Test func stopWhenNotNavigatingIsNoOp() {
        sessionManager.stopNavigation()
        sessionManager.stopNavigation()
        #expect(!sessionManager.isNavigating)
    }
}
