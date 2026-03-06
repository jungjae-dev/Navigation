import MapKit
import CoreLocation

final class AppleRouteService: RouteProviding {

    // MARK: - Private

    private var currentDirections: MKDirections?
    private let maxRetryCount = 3

    // MARK: - RouteProviding

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        cancelCurrentRequest()

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = transportMode.mkTransportType
        request.requestsAlternateRoutes = true

        let mkRoutes = try await performWithRetry(request: request)
        return mkRoutes.map { AppleModelConverter.route(from: $0) }
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        let response = try await directions.calculateETA()
        return response.expectedTravelTime
    }

    func cancelCurrentRequest() {
        currentDirections?.cancel()
        currentDirections = nil
    }

    // MARK: - Private

    private func performWithRetry(
        request: MKDirections.Request,
        attempt: Int = 0
    ) async throws -> [MKRoute] {
        let directions = MKDirections(request: request)
        currentDirections = directions

        do {
            let response = try await directions.calculate()
            guard !response.routes.isEmpty else {
                throw LBSError.noRoutesFound
            }
            return response.routes
        } catch let error as LBSError {
            throw error
        } catch {
            if attempt < maxRetryCount - 1 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                return try await performWithRetry(request: request, attempt: attempt + 1)
            }
            throw LBSError.networkError(error.localizedDescription)
        }
    }
}
