import CoreLocation
@testable import Navigation

final class MockRouteService: RouteProviding {

    var mockRoutes: [Route] = []
    var mockETA: TimeInterval = 600
    var shouldThrow: LBSError?
    var calculateRoutesCallCount = 0
    var lastHeading: CLLocationDirection?

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        heading: CLLocationDirection?,
        transportMode: TransportMode
    ) async throws -> [Route] {
        calculateRoutesCallCount += 1
        lastHeading = heading
        if let error = shouldThrow { throw error }
        return mockRoutes
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        if let error = shouldThrow { throw error }
        return mockETA
    }

    func cancelCurrentRequest() {}
}
