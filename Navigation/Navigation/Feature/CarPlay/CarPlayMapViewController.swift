import UIKit
import MapKit
import Combine

final class CarPlayMapViewController: UIViewController {

    // MARK: - UI

    private let mapView: TouchObservableMapView = {
        let map = TouchObservableMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        map.mapType = .standard
        return map
    }()

    // MARK: - Properties

    private let locationService: LocationService
    private let sessionManager: NavigationSessionManager
    private lazy var userLocationPresenter = UserLocationPresenter(
        mapView: mapView,
        headingSource: .locationCourse,
        locationService: locationService
    )
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

        userLocationPresenter.attach()
        mapView.onUserTouch = { [weak self] in
            self?.userLocationPresenter.userDidInteractWithMap()
        }
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
        // 주행 시작/종료 — 카메라 모드 전환만 담당
        sessionManager.navigationCommandPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] command in
                switch command {
                case .started:
                    self?.enterNavigationCamera()
                case .stopped:
                    self?.exitNavigationCamera()
                }
            }
            .store(in: &cancellables)

        // 경로 변경 (초기 발행 + reroute) — overlay 만 담당
        sessionManager.routePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                if let route {
                    self?.applyRouteOverlay(route)
                } else {
                    self?.clearRouteOverlay()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Route Overlay (publisher-driven)

    private func applyRouteOverlay(_ route: Route) {
        if let old = routeOverlay {
            mapView.removeOverlay(old)
        }
        let polyline = route.mkPolyline
        mapView.addOverlay(polyline, level: .aboveRoads)
        routeOverlay = polyline
    }

    private func clearRouteOverlay() {
        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
            routeOverlay = nil
        }
    }

    // MARK: - Navigation Camera (command-driven)

    private func enterNavigationCamera() {
        // 현재 overlay 가 있으면 fit, 없으면 다음 routePublisher 발행 후 follow 가 잡아줌
        if let overlay = routeOverlay {
            mapView.setVisibleMapRect(
                overlay.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
                animated: true
            )
        }

        // 주행 중 location follow + heading
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

    private func exitNavigationCamera() {
        navigationCancellables.removeAll()

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

    func showRoute(_ route: Route) {
        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
        }
        let polyline = route.mkPolyline
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

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
        if let view = userLocationPresenter.makeAnnotationView(for: annotation) {
            return view
        }
        return nil
    }

}
