import CoreLocation

final class FallbackRouteService: RouteProviding {

    private let primary: RouteProviding
    private let fallback: RouteProviding
    private var isPrimaryAvailable = true

    private let recoveryInterval: TimeInterval
    private(set) var lastQuotaExceededDate: Date?

    init(
        primary: RouteProviding,
        fallback: RouteProviding,
        recoveryInterval: TimeInterval = 3600
    ) {
        self.primary = primary
        self.fallback = fallback
        self.recoveryInterval = recoveryInterval
    }

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        heading: CLLocationDirection?,
        transportMode: TransportMode
    ) async throws -> [Route] {
        checkRecovery()

        if isPrimaryAvailable {
            do {
                let routes = try await primary.calculateRoutes(
                    from: origin, to: destination, heading: heading, transportMode: transportMode
                )
                logRouteResult(routes, label: "primary")
                return routes
            } catch let error as LBSError where error == .quotaExceeded {
                markPrimaryUnavailable()
                let routes = try await fallback.calculateRoutes(
                    from: origin, to: destination, heading: heading, transportMode: transportMode
                )
                logRouteResult(routes, label: "fallback/quota")
                return routes
            } catch let error as LBSError where error == .noRoutesFound {
                let routes = try await fallback.calculateRoutes(
                    from: origin, to: destination, heading: heading, transportMode: transportMode
                )
                logRouteResult(routes, label: "fallback/noRoute")
                return routes
            }
        }

        let routes = try await fallback.calculateRoutes(
            from: origin, to: destination, heading: heading, transportMode: transportMode
        )
        logRouteResult(routes, label: "fallback")
        return routes
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        checkRecovery()

        if isPrimaryAvailable {
            do {
                return try await primary.calculateETA(from: origin, to: destination)
            } catch let error as LBSError where error == .quotaExceeded {
                markPrimaryUnavailable()
                return try await fallback.calculateETA(from: origin, to: destination)
            }
        }

        return try await fallback.calculateETA(from: origin, to: destination)
    }

    func cancelCurrentRequest() {
        primary.cancelCurrentRequest()
        fallback.cancelCurrentRequest()
    }

    // MARK: - Private

    private func markPrimaryUnavailable() {
        isPrimaryAvailable = false
        lastQuotaExceededDate = Date()
        NotificationCenter.default.post(
            name: .lbsRouteFallbackActivated, object: nil
        )
    }

    private func logRouteResult(_ result: [Route], label: String) {
    }

    private func checkRecovery() {
        guard !isPrimaryAvailable,
              let lastDate = lastQuotaExceededDate,
              Date().timeIntervalSince(lastDate) > recoveryInterval else { return }
        isPrimaryAvailable = true
    }
}

