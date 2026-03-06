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
        transportMode: TransportMode
    ) async throws -> [Route] {
        checkRecovery()

        if isPrimaryAvailable {
            do {
                return try await primary.calculateRoutes(
                    from: origin, to: destination, transportMode: transportMode
                )
            } catch let error as LBSError where error == .quotaExceeded {
                markPrimaryUnavailable()
                return try await fallback.calculateRoutes(
                    from: origin, to: destination, transportMode: transportMode
                )
            } catch let error as LBSError where error == .noRoutesFound {
                return try await fallback.calculateRoutes(
                    from: origin, to: destination, transportMode: transportMode
                )
            }
        }

        return try await fallback.calculateRoutes(
            from: origin, to: destination, transportMode: transportMode
        )
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
            name: .lbsProviderFallbackActivated, object: nil
        )
    }

    private func checkRecovery() {
        guard !isPrimaryAvailable,
              let lastDate = lastQuotaExceededDate,
              Date().timeIntervalSince(lastDate) > recoveryInterval else { return }
        isPrimaryAvailable = true
    }
}

extension Notification.Name {
    static let lbsProviderFallbackActivated = Notification.Name("lbsProviderFallbackActivated")
}
