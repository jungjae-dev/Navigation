import MapKit
import Combine

final class MapCamera {

    // MARK: - Publishers

    let isAutoTrackingPublisher = CurrentValueSubject<Bool, Never>(true)

    // MARK: - Configuration

    private let defaultPitch: CGFloat = 45.0
    private let defaultHeading: CLLocationDirection = 0.0

    // MARK: - Public

    func enableAutoTracking() {
        isAutoTrackingPublisher.send(true)
    }

    func disableAutoTracking() {
        isAutoTrackingPublisher.send(false)
    }

    /// Create a 3D navigation camera based on current speed
    func createNavigationCamera(
        center: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        speed: CLLocationSpeed
    ) -> MKMapCamera {
        let altitude = cameraAltitude(for: speed)
        let camera = MKMapCamera()
        camera.centerCoordinate = center
        camera.heading = heading
        camera.pitch = defaultPitch
        camera.centerCoordinateDistance = altitude
        return camera
    }

    // MARK: - Private

    /// Speed-based altitude:
    /// - Stopped/slow (< 5 m/s): 500m — close zoom for detail
    /// - City driving (5–22 m/s): 1000m — balanced view
    /// - Highway (> 22 m/s / ~80 km/h): 2000m — wider perspective
    private func cameraAltitude(for speed: CLLocationSpeed) -> CLLocationDistance {
        if speed < 5 {
            return 500
        } else if speed <= 22 {
            // Linear interpolation between 500 and 1000
            let t = (speed - 5.0) / 17.0
            return 500 + t * 500
        } else if speed <= 33 {
            // Linear interpolation between 1000 and 2000
            let t = (speed - 22.0) / 11.0
            return 1000 + t * 1000
        } else {
            return 2000
        }
    }
}
