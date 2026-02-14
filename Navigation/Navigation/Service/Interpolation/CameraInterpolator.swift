import MapKit
import QuartzCore

/// Interpolates MKMapCamera properties for smooth transitions
final class CameraInterpolator {

    // MARK: - State

    private var previousCamera: MKMapCamera?
    private var targetCamera: MKMapCamera?
    private var updateTimestamp: CFTimeInterval = 0
    private var interpolationDuration: CFTimeInterval = 1.0

    // MARK: - Public

    func updateTarget(_ camera: MKMapCamera) {
        previousCamera = targetCamera ?? camera
        targetCamera = camera
        updateTimestamp = CACurrentMediaTime()
        interpolationDuration = 1.0
    }

    func interpolate(at timestamp: CFTimeInterval) -> MKMapCamera? {
        guard let prev = previousCamera,
              let target = targetCamera else {
            return targetCamera
        }

        let elapsed = timestamp - updateTimestamp
        let t = min(max(elapsed / interpolationDuration, 0), 1)

        let camera = MKMapCamera()

        // Interpolate center coordinate
        camera.centerCoordinate = CLLocationCoordinate2D(
            latitude: prev.centerCoordinate.latitude + (target.centerCoordinate.latitude - prev.centerCoordinate.latitude) * t,
            longitude: prev.centerCoordinate.longitude + (target.centerCoordinate.longitude - prev.centerCoordinate.longitude) * t
        )

        // Interpolate heading with shortest-arc
        let headingDelta = ((target.heading - prev.heading + 540).truncatingRemainder(dividingBy: 360)) - 180
        var heading = prev.heading + headingDelta * t
        if heading < 0 { heading += 360 }
        if heading >= 360 { heading -= 360 }
        camera.heading = heading

        // Interpolate altitude
        camera.centerCoordinateDistance = prev.centerCoordinateDistance + (target.centerCoordinateDistance - prev.centerCoordinateDistance) * t

        // Interpolate pitch
        camera.pitch = prev.pitch + (target.pitch - prev.pitch) * t

        return camera
    }

    func reset() {
        previousCamera = nil
        targetCamera = nil
    }
}
