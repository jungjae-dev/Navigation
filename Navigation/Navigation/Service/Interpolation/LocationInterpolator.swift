import CoreLocation
import QuartzCore

/// Linearly interpolates GPS coordinates between updates for smooth rendering
final class LocationInterpolator {

    // MARK: - State

    private var previousCoordinate: CLLocationCoordinate2D?
    private var targetCoordinate: CLLocationCoordinate2D?
    private var previousSpeed: CLLocationSpeed = 0
    private var targetSpeed: CLLocationSpeed = 0
    private var updateTimestamp: CFTimeInterval = 0
    private var interpolationDuration: CFTimeInterval = 1.0

    // MARK: - Public

    func updateTarget(_ location: CLLocation) {
        previousCoordinate = targetCoordinate ?? location.coordinate
        previousSpeed = targetSpeed
        targetCoordinate = location.coordinate
        targetSpeed = max(location.speed, 0)
        updateTimestamp = CACurrentMediaTime()

        // Estimate duration until next GPS update (~1 second typical)
        interpolationDuration = 1.0
    }

    func interpolate(at timestamp: CFTimeInterval) -> CLLocationCoordinate2D? {
        guard let prev = previousCoordinate,
              let target = targetCoordinate else {
            return targetCoordinate
        }

        let elapsed = timestamp - updateTimestamp
        let t = min(max(elapsed / interpolationDuration, 0), 1)

        let lat = prev.latitude + (target.latitude - prev.latitude) * t
        let lon = prev.longitude + (target.longitude - prev.longitude) * t

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func interpolatedSpeed(at timestamp: CFTimeInterval) -> CLLocationSpeed {
        let elapsed = timestamp - updateTimestamp
        let t = min(max(elapsed / interpolationDuration, 0), 1)
        return previousSpeed + (targetSpeed - previousSpeed) * t
    }

    func reset() {
        previousCoordinate = nil
        targetCoordinate = nil
        previousSpeed = 0
        targetSpeed = 0
    }
}
