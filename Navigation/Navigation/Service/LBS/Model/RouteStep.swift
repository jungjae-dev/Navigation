import CoreLocation

struct RouteStep: Sendable {
    let instructions: String
    let distance: CLLocationDistance
    let polylineCoordinates: [CLLocationCoordinate2D]
}
