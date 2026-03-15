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
            let priorities: [(value: String, name: String)] = [
                ("RECOMMEND", "추천"),
                ("TIME", "최단시간"),
            ]

            let routes: [Route] = try await withThrowingTaskGroup(of: Route?.self) { group in
                for priority in priorities {
                    group.addTask {
                        let queryItems = [
                            URLQueryItem(name: "origin", value: "\(origin.longitude),\(origin.latitude)"),
                            URLQueryItem(name: "destination", value: "\(destination.longitude),\(destination.latitude)"),
                            URLQueryItem(name: "priority", value: priority.value),
                        ]

                        let response: KakaoRouteResponse = try await KakaoAPIClient.shared.request(
                            baseURL: KakaoAPIConfig.BaseURL.mobility,
                            path: "/v1/directions",
                            queryItems: queryItems,
                            apiKey: KakaoAPIConfig.restAPIKey
                        )

                        guard let kakaoRoute = response.routes.first(where: { $0.resultCode == 0 }) else {
                            return nil
                        }

                        var route = KakaoModelConverter.route(from: kakaoRoute)
                        route.name = priority.name
                        return route
                    }
                }

                var results: [Route] = []
                for try await route in group {
                    if let route { results.append(route) }
                }
                return results
            }

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
