import CoreLocation

protocol RouteProviding: AnyObject {

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        heading: CLLocationDirection?,
        transportMode: TransportMode
    ) async throws -> [Route]

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval

    func cancelCurrentRequest()
}
