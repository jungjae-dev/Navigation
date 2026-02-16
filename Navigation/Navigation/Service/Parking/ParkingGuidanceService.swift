import Foundation
import MapKit
import CoreLocation
import Combine

/// Manages parking approach mode: zooms in, activates 3D building view,
/// and shows entry direction marker when approaching destination
final class ParkingGuidanceService {

    // MARK: - Publishers

    let isActivePublisher = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Configuration

    private let approachAltitude: CLLocationDistance = 150.0
    private let approachPitch: CGFloat = 60.0
    private let approachHeadingDistance: CLLocationDistance = 200.0

    // MARK: - State

    private var destination: CLLocationCoordinate2D?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public

    /// Configure the service with a destination coordinate
    func configure(destination: CLLocationCoordinate2D) {
        self.destination = destination
    }

    /// Activate parking guidance mode on the given map view controller
    func activate(on mapViewController: MapViewController) {
        guard let destination else { return }

        isActivePublisher.send(true)

        // Configure map for parking guidance
        mapViewController.configureForParkingGuidance()

        // Set up 3D camera pointing at destination
        let camera = MKMapCamera(
            lookingAtCenter: destination,
            fromDistance: approachAltitude,
            pitch: approachPitch,
            heading: 0
        )
        mapViewController.setCamera(camera, animated: true)

        // Show entry direction marker
        mapViewController.showParkingEntryMarker(at: destination)
    }

    /// Deactivate parking guidance and restore standard navigation view
    func deactivate(on mapViewController: MapViewController) {
        isActivePublisher.send(false)
        mapViewController.removeParkingEntryMarker()
    }

    /// Reset the service
    func reset() {
        destination = nil
        isActivePublisher.send(false)
        cancellables.removeAll()
    }
}
