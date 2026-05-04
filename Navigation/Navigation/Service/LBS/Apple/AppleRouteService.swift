import MapKit
import CoreLocation

final class AppleRouteService: RouteProviding {

    // MARK: - Private

    private var currentDirections: MKDirections?
    private let maxRetryCount = 3

    // MKDirections 는 heading 입력을 지원하지 않아 방향 강제 불가.
    // alternates 중 heading 에 가장 가까운 경로를 best-effort 로 선택.
    // 역방향 경로가 와도 NavigationEngine 의 bearing 검증 skip 으로 무한루프 없음.
    private let alignmentToleranceDegrees: Double = 90

    // MARK: - RouteProviding

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        heading: CLLocationDirection?,
        transportMode: TransportMode
    ) async throws -> [Route] {
        cancelCurrentRequest()

        let routes = try await fetchSimpleRoutes(from: origin, to: destination, transportMode: transportMode)

        // heading 이 있고 자동차 모드면 alternates 중 방향이 가장 맞는 경로 우선 선택 (best-effort)
        if let heading,
           heading.isFinite, (0...360).contains(heading),
           transportMode == .automobile,
           let best = pickAligned(routes, heading: heading) {
            return [best]
        }

        return routes
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


    // MARK: - Bearing helpers (MapGeometry 위임)

    private static func firstBearing(of polyline: [CLLocationCoordinate2D]) -> CLLocationDirection? {
        MapGeometry.firstBearing(of: polyline)
    }

    private static func angleDelta(_ a: CLLocationDirection, _ b: CLLocationDirection) -> Double {
        MapGeometry.angleDelta(a, b)
    }
}
