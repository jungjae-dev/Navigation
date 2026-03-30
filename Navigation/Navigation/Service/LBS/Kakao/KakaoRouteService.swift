import CoreLocation

final class KakaoRouteService: RouteProviding {

    private var currentTask: Task<[Route], Error>?

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        cancelCurrentRequest()

        switch transportMode {
        case .automobile:
            return try await calculateDrivingRoutes(from: origin, to: destination)
        case .walking:
            return try await calculateWalkingRoutes(from: origin, to: destination)
        }
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

    // MARK: - 자동차 경로

    private func calculateDrivingRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [Route] {
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

    // MARK: - 도보 경로

    private func calculateWalkingRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [Route] {
        let task = Task { () -> [Route] in
            // 도보 API 미승인(403) 시 noRoutesFound로 변환 → FallbackService가 Apple로 폴백
            do { return try await fetchWalkingRoutes(from: origin, to: destination) }
            catch { throw LBSError.noRoutesFound }
        }

        currentTask = task
        return try await task.value
    }

    private func fetchWalkingRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [Route] {
        let priorities: [(value: String, name: String)] = [
            ("DISTANCE", "최단거리"),
            ("MAIN_STREET", "큰길우선"),
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
                        path: "/affiliate/walking/v1/directions",
                        queryItems: queryItems,
                        apiKey: KakaoAPIConfig.restAPIKey,
                        additionalHeaders: ["service": "routin"]
                    )

                    guard let kakaoRoute = response.routes.first(where: { $0.resultCode == 0 }) else {
                        return nil
                    }

                    var route = KakaoModelConverter.route(from: kakaoRoute, transportMode: .walking)
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
}
