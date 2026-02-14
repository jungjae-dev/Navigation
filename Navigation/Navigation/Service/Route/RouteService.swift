import MapKit
import CoreLocation

final class RouteService {

    // MARK: - Private

    private var currentDirections: MKDirections?
    private let maxRetryCount = 3

    // MARK: - Public Methods

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType = .automobile
    ) async throws -> [MKRoute] {
        cancelCurrentRequest()

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = transportType
        request.requestsAlternateRoutes = true

        return try await performWithRetry(request: request)
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> MKDirections.ETAResponse {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        return try await directions.calculateETA()
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
                throw RouteServiceError.noRoutesFound
            }
            return response.routes
        } catch let error as RouteServiceError {
            throw error
        } catch {
            if attempt < maxRetryCount - 1 {
                // Exponential backoff: 1s, 2s, 4s
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                return try await performWithRetry(request: request, attempt: attempt + 1)
            }
            throw RouteServiceError.networkError(error)
        }
    }
}

// MARK: - Error

enum RouteServiceError: Error, LocalizedError {
    case noRoutesFound
    case networkError(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noRoutesFound:
            return "경로를 찾을 수 없습니다"
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .cancelled:
            return "경로 탐색이 취소되었습니다"
        }
    }
}
