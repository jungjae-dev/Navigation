import MapKit
import CoreLocation

final class AppleRouteService: RouteProviding {

    // MARK: - Private

    private var currentDirections: MKDirections?
    private let maxRetryCount = 3

    // 차로 인식 projection 설정 (한국=우측통행 기준)
    private let projectionForwardDistance: CLLocationDistance = 50
    private let projectionLateralOffset: CLLocationDistance = 3.0
    private let headingSpeedGate: CLLocationSpeed = 3.0     // m/s 미만이면 heading 무시
    private let alignmentToleranceDegrees: Double = 60      // leg2 alternates 필터 임계값

    // MARK: - RouteProviding

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        heading: CLLocationDirection?,
        transportMode: TransportMode
    ) async throws -> [Route] {
        cancelCurrentRequest()

        // heading 없거나 도보 → 단순 경로
        guard let heading,
              heading.isFinite, (0...360).contains(heading),
              transportMode == .automobile else {
            return try await fetchSimpleRoutes(
                from: origin, to: destination, transportMode: transportMode
            )
        }

        // 차로 인식 projection + 2-leg 합성
        let waypoint = projectLaneAware(
            origin,
            heading: heading,
            forwardDistance: projectionForwardDistance,
            lateralOffset: projectionLateralOffset
        )

        do {
            async let leg1Task = fetchSimpleRoutes(from: origin, to: waypoint, transportMode: .automobile)
            async let leg2Task = fetchSimpleRoutes(from: waypoint, to: destination, transportMode: .automobile)
            let (leg1Routes, leg2Routes) = try await (leg1Task, leg2Task)

            guard let leg1 = leg1Routes.first,
                  let leg2 = pickAligned(leg2Routes, heading: heading) else {
                throw LBSError.noRoutesFound
            }
            return [Self.concatenate(leg1: leg1, leg2: leg2)]
        } catch {
            // 합성 실패 시 단순 경로로 fallback
            return try await fetchSimpleRoutes(
                from: origin, to: destination, transportMode: transportMode
            )
        }
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

    // MARK: - Simple route fetch

    private func fetchSimpleRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
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

    // MARK: - Lane-aware projection

    /// 진행방향 forwardDistance 미터 앞 + 진행방향 우측 lateralOffset 미터
    /// 한국=우측통행 가정. LHT 국가(JP/UK)에선 lateralOffset 부호 반전 필요.
    private func projectLaneAware(
        _ origin: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        forwardDistance: CLLocationDistance,
        lateralOffset: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let bearingRad = heading * .pi / 180
        let rightBearingRad = (heading + 90) * .pi / 180

        // ENU 평면 변위 (m)
        let dxEast  = forwardDistance * sin(bearingRad)      + lateralOffset * sin(rightBearingRad)
        let dyNorth = forwardDistance * cos(bearingRad)      + lateralOffset * cos(rightBearingRad)

        // 미터 → 위경도 (한국 위도에서 충분히 정확)
        let earthRadius = 6_371_000.0
        let dLat = (dyNorth / earthRadius) * 180 / .pi
        let cosLat = cos(origin.latitude * .pi / 180)
        let dLon = (dxEast / (earthRadius * max(cosLat, 0.0001))) * 180 / .pi

        return CLLocationCoordinate2D(
            latitude: origin.latitude + dLat,
            longitude: origin.longitude + dLon
        )
    }

    /// alternates 중 첫 segment bearing 이 user heading 과 ±tolerance 이내인 경로 선택
    private func pickAligned(_ routes: [Route], heading: CLLocationDirection) -> Route? {
        let scored: [(Route, Double)] = routes.compactMap { route in
            guard let b = Self.firstBearing(of: route.polylineCoordinates) else { return nil }
            return (route, abs(Self.angleDelta(heading, b)))
        }
        let aligned = scored.filter { $0.1 <= alignmentToleranceDegrees }
            .sorted { $0.1 < $1.1 }
        return aligned.first?.0 ?? scored.sorted { $0.1 < $1.1 }.first?.0
    }

    // MARK: - Concatenation

    private static func concatenate(leg1: Route, leg2: Route) -> Route {
        var polyline = leg1.polylineCoordinates
        // 두 leg 의 연결 지점(waypoint) 중복 제거 — 1m 이내면 동일 점으로 간주
        if let last = polyline.last,
           let firstOfLeg2 = leg2.polylineCoordinates.first {
            let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: firstOfLeg2.latitude, longitude: firstOfLeg2.longitude))
            if dist < 1.0 {
                polyline.append(contentsOf: leg2.polylineCoordinates.dropFirst())
            } else {
                polyline.append(contentsOf: leg2.polylineCoordinates)
            }
        } else {
            polyline.append(contentsOf: leg2.polylineCoordinates)
        }

        return Route(
            id: UUID().uuidString,
            distance: leg1.distance + leg2.distance,
            expectedTravelTime: leg1.expectedTravelTime + leg2.expectedTravelTime,
            name: leg2.name,
            steps: leg1.steps + leg2.steps,
            polylineCoordinates: polyline,
            transportMode: leg2.transportMode,
            provider: leg2.provider
        )
    }

    // MARK: - Bearing helpers (MapGeometry 위임)

    private static func firstBearing(of polyline: [CLLocationCoordinate2D]) -> CLLocationDirection? {
        MapGeometry.firstBearing(of: polyline)
    }

    private static func angleDelta(_ a: CLLocationDirection, _ b: CLLocationDirection) -> Double {
        MapGeometry.angleDelta(a, b)
    }
}
