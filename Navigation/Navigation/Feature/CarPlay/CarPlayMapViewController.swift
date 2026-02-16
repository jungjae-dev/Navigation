import UIKit
import MapKit
import Combine

final class CarPlayMapViewController: UIViewController {

    // MARK: - UI

    private let mapView: MKMapView = {
        let map = MKMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        map.showsUserLocation = true
        map.mapType = .standard
        return map
    }()

    // MARK: - Properties

    private let locationService: LocationService
    private let sessionManager: NavigationSessionManager
    private var cancellables = Set<AnyCancellable>()
    private var navigationCancellables = Set<AnyCancellable>()
    private var routeOverlay: MKPolyline?
    private var isInitialLocationSet = false

    // MARK: - Init

    init(locationService: LocationService, sessionManager: NavigationSessionManager) {
        self.locationService = locationService
        self.sessionManager = sessionManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapView()
        bindLocation()
        bindNavigationSession()
    }

    // MARK: - Setup

    private func setupMapView() {
        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        mapView.delegate = self
    }

    // MARK: - Bindings

    private func bindLocation() {
        locationService.locationPublisher
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self, !isInitialLocationSet else { return }
                isInitialLocationSet = true
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                mapView.setRegion(region, animated: false)
            }
            .store(in: &cancellables)
    }

    private func bindNavigationSession() {
        sessionManager.activeSessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                if let session {
                    self?.configureForNavigation(session: session)
                } else {
                    self?.configureForStandard()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation Mode

    private func configureForNavigation(session: NavigationSession) {
        // Clear previous overlay
        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
        }

        // Add route overlay
        let polyline = session.route.polyline
        mapView.addOverlay(polyline, level: .aboveRoads)
        routeOverlay = polyline

        // Fit route on map initially
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
            animated: true
        )

        // Follow user location with heading during navigation
        navigationCancellables.removeAll()

        locationService.locationPublisher
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self else { return }
                let heading = location.course >= 0 ? location.course : 0
                let camera = MKMapCamera(
                    lookingAtCenter: location.coordinate,
                    fromDistance: 1000,
                    pitch: 45,
                    heading: heading
                )
                mapView.setCamera(camera, animated: true)
            }
            .store(in: &navigationCancellables)
    }

    private func configureForStandard() {
        navigationCancellables.removeAll()

        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
            routeOverlay = nil
        }

        // Reset to 2D view
        let camera = MKMapCamera()
        camera.pitch = 0
        camera.heading = 0
        if let userLocation = locationService.locationPublisher.value {
            camera.centerCoordinate = userLocation.coordinate
            camera.centerCoordinateDistance = 1000
        }
        mapView.setCamera(camera, animated: true)
    }

    // MARK: - Public

    func showRoute(_ route: MKRoute) {
        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
        }
        let polyline = route.polyline
        mapView.addOverlay(polyline, level: .aboveRoads)
        routeOverlay = polyline

        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
            animated: true
        )
    }

    func clearRoute() {
        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
            routeOverlay = nil
        }
    }
}

// MARK: - MKMapViewDelegate

extension CarPlayMapViewController: MKMapViewDelegate {

    nonisolated func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        MainActor.assumeIsolated {
            if let polyline = overlay as? MKPolyline {
                return RouteOverlayRenderer(polyline: polyline, isPrimary: true)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
