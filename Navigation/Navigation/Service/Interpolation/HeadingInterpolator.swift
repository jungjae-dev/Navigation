import CoreLocation
import QuartzCore

/// Interpolates heading/direction using shortest-arc rotation
final class HeadingInterpolator {

    // MARK: - State

    private var previousHeading: CLLocationDirection = 0
    private var targetHeading: CLLocationDirection = 0
    private var updateTimestamp: CFTimeInterval = 0
    private var interpolationDuration: CFTimeInterval = 1.0

    // MARK: - Public

    func updateTarget(_ heading: CLLocationDirection) {
        previousHeading = targetHeading
        targetHeading = heading
        updateTimestamp = CACurrentMediaTime()
        interpolationDuration = 1.0
    }

    func interpolate(at timestamp: CFTimeInterval) -> CLLocationDirection {
        let elapsed = timestamp - updateTimestamp
        let t = min(max(elapsed / interpolationDuration, 0), 1)

        // Shortest-arc interpolation: ((target - prev + 540) % 360) - 180
        let delta = ((targetHeading - previousHeading + 540).truncatingRemainder(dividingBy: 360)) - 180
        var result = previousHeading + delta * t

        // Normalize to [0, 360)
        if result < 0 { result += 360 }
        if result >= 360 { result -= 360 }

        return result
    }

    func reset() {
        previousHeading = 0
        targetHeading = 0
    }
}
