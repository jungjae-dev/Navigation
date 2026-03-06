import Testing
import CoreLocation
@testable import Navigation

struct FallbackRouteServiceTests {

    private let origin = TestFixtures.gangnam
    private let destination = TestFixtures.seolleung

    @Test func primarySucceeds_fallbackNotCalled() async throws {
        let primary = MockRouteService()
        primary.mockRoutes = [TestFixtures.sampleRoute]
        let fallback = MockRouteService()
        fallback.mockRoutes = []

        let service = FallbackRouteService(primary: primary, fallback: fallback)
        let routes = try await service.calculateRoutes(
            from: origin, to: destination, transportMode: .automobile
        )

        #expect(routes.count == 1)
        #expect(primary.calculateRoutesCallCount == 1)
        #expect(fallback.calculateRoutesCallCount == 0)
    }

    @Test func quotaExceeded_fallsBackToSecondary() async throws {
        let primary = MockRouteService()
        primary.shouldThrow = .quotaExceeded

        let fallback = MockRouteService()
        fallback.mockRoutes = [TestFixtures.sampleRoute]

        let service = FallbackRouteService(primary: primary, fallback: fallback)
        let routes = try await service.calculateRoutes(
            from: origin, to: destination, transportMode: .automobile
        )

        #expect(routes.count == 1)
        #expect(primary.calculateRoutesCallCount == 1)
        #expect(fallback.calculateRoutesCallCount == 1)
    }

    @Test func noRoutesFound_fallsBackToSecondary() async throws {
        let primary = MockRouteService()
        primary.shouldThrow = .noRoutesFound

        let fallback = MockRouteService()
        fallback.mockRoutes = [TestFixtures.walkingRoute]

        let service = FallbackRouteService(primary: primary, fallback: fallback)
        let routes = try await service.calculateRoutes(
            from: origin, to: destination, transportMode: .walking
        )

        #expect(routes.count == 1)
        #expect(fallback.calculateRoutesCallCount == 1)
    }

    @Test func afterQuotaExceeded_primarySkippedUntilRecovery() async throws {
        let primary = MockRouteService()
        primary.shouldThrow = .quotaExceeded

        let fallback = MockRouteService()
        fallback.mockRoutes = [TestFixtures.sampleRoute]

        let service = FallbackRouteService(primary: primary, fallback: fallback, recoveryInterval: 3600)

        // First call: primary fails → fallback
        _ = try await service.calculateRoutes(
            from: origin, to: destination, transportMode: .automobile
        )

        // Second call: primary should be skipped
        _ = try await service.calculateRoutes(
            from: origin, to: destination, transportMode: .automobile
        )

        #expect(primary.calculateRoutesCallCount == 1)
        #expect(fallback.calculateRoutesCallCount == 2)
    }

    @Test func etaFallback_quotaExceeded() async throws {
        let primary = MockRouteService()
        primary.shouldThrow = .quotaExceeded

        let fallback = MockRouteService()
        fallback.mockETA = 900

        let service = FallbackRouteService(primary: primary, fallback: fallback)
        let eta = try await service.calculateETA(from: origin, to: destination)

        #expect(eta == 900)
    }
}
