import CoreLocation

final class KakaoRouteService: RouteProviding {

    private var currentTask: Task<[Route], Error>?

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        cancelCurrentRequest()

        guard transportMode == .automobile else {
            throw LBSError.noRoutesFound
        }

        let task = Task {
            let queryItems = [
                URLQueryItem(name: "origin", value: "\(origin.longitude),\(origin.latitude)"),
                URLQueryItem(name: "destination", value: "\(destination.longitude),\(destination.latitude)"),
                URLQueryItem(name: "alternatives", value: "true"),
            ]

            let response: KakaoRouteResponse = try await KakaoAPIClient.shared.request(
                baseURL: KakaoAPIConfig.BaseURL.mobility,
                path: "/v1/directions",
                queryItems: queryItems,
                apiKey: KakaoAPIConfig.mobilityAppKey
            )

            let routes = response.routes
                .filter { $0.resultCode == 0 }
                .map { KakaoModelConverter.route(from: $0) }

            guard !routes.isEmpty else { throw LBSError.noRoutesFound }
            return routes
        }

        currentTask = task
        return try await task.value
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        let routes = try await calculateRoutes(
            from: origin, to: destination, transportMode: .automobile
        )
        guard let first = routes.first else { throw LBSError.noRoutesFound }
        return first.expectedTravelTime
    }

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
}
