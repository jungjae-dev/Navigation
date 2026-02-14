import UIKit
import MapKit
import CoreLocation
import Combine

struct InterpolatedLocation {
    let coordinate: CLLocationCoordinate2D
    let heading: CLLocationDirection
    let speed: CLLocationSpeed
}

/// CADisplayLink-based 60fps interpolation coordinator
/// Combines location, heading, and camera interpolation for smooth map rendering
final class MapInterpolator {

    // MARK: - Publishers

    let interpolatedLocationPublisher = CurrentValueSubject<InterpolatedLocation?, Never>(nil)

    // MARK: - Dependencies

    private let locationInterpolator = LocationInterpolator()
    private let headingInterpolator = HeadingInterpolator()
    private let cameraInterpolator = CameraInterpolator()
    private let mapCamera: MapCamera

    // MARK: - State

    private var displayLink: CADisplayLink?
    private weak var mapViewController: MapViewController?
    private var lastSpeed: CLLocationSpeed = 0

    // MARK: - Init

    init(mapCamera: MapCamera) {
        self.mapCamera = mapCamera
    }

    // MARK: - Public

    func start(mapViewController: MapViewController) {
        self.mapViewController = mapViewController
        stop() // ensure no duplicate

        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        locationInterpolator.reset()
        headingInterpolator.reset()
        cameraInterpolator.reset()
        interpolatedLocationPublisher.send(nil)
    }

    /// Call this when a new GPS location arrives
    func updateTarget(location: CLLocation, heading: CLLocationDirection) {
        locationInterpolator.updateTarget(location)
        headingInterpolator.updateTarget(heading)
        lastSpeed = max(location.speed, 0)

        // Create target camera and push to interpolator
        guard let coord = locationInterpolator.interpolate(at: CACurrentMediaTime()) else { return }
        let camera = mapCamera.createNavigationCamera(
            center: coord,
            heading: heading,
            speed: lastSpeed
        )
        cameraInterpolator.updateTarget(camera)
    }

    // MARK: - CADisplayLink

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let timestamp = CACurrentMediaTime()

        guard let coord = locationInterpolator.interpolate(at: timestamp) else { return }
        let heading = headingInterpolator.interpolate(at: timestamp)
        let speed = locationInterpolator.interpolatedSpeed(at: timestamp)

        // Publish interpolated location
        let interpolated = InterpolatedLocation(
            coordinate: coord,
            heading: heading,
            speed: speed
        )
        interpolatedLocationPublisher.send(interpolated)

        // Apply camera only if auto-tracking is enabled
        guard mapCamera.isAutoTrackingPublisher.value else { return }

        if let camera = cameraInterpolator.interpolate(at: timestamp) {
            mapViewController?.applyCamera(camera, animated: false)
        }
    }
}
