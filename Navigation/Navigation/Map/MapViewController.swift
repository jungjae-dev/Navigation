import UIKit
import MapKit
import Combine

final class MapViewController: UIViewController {

    // MARK: - Properties

    let mapView = MKMapView()
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()
    private var hasMovedToInitialLocation = false

    // MARK: - Search & Route State

    private var searchResultAnnotations: [SearchResultAnnotation] = []
    private var destinationAnnotation: DestinationAnnotation?
    private var routeOverlays: [MKPolyline] = []
    private var routeIsPrimary: [MKPolyline: Bool] = [:]

    /// Callback when a search result marker is tapped. Returns the index.
    var onAnnotationSelected: ((Int) -> Void)?

    /// Callback when a built-in POI is tapped.
    var onPOISelected: ((MKMapItem) -> Void)?

    // MARK: - Navigation Mode State

    private var isNavigationMode = false
    private var navigationRouteOverlay: MKPolyline?
    private var panGestureRecognizer: UIPanGestureRecognizer?

    /// Called when the user pans/interacts with the map during navigation
    var onUserInteraction: (() -> Void)?

    // MARK: - Init

    init(locationService: LocationService) {
        self.locationService = locationService
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
    }

    // MARK: - Setup

    private func setupMapView() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.selectableMapFeatures = [.pointsOfInterest]
    }

    // MARK: - Binding

    private func bindLocation() {
        locationService.locationPublisher
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    // MARK: - Location Handling

    private func handleLocationUpdate(_ location: CLLocation) {
        guard !hasMovedToInitialLocation else { return }
        hasMovedToInitialLocation = true

        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        mapView.setRegion(region, animated: false)
    }

    // MARK: - Public: Map Insets

    func updateMapInsets(top: CGFloat, bottom: CGFloat) {
        mapView.layoutMargins = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
    }

    func resetMapInsets() {
        mapView.layoutMargins = .zero
    }

    // MARK: - Public: General

    func moveToLocation(_ coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        mapView.setRegion(region, animated: animated)
    }

    // MARK: - Public: Search Results

    func showSearchResults(_ mapItems: [MKMapItem]) {
        clearSearchResults()

        let annotations = mapItems.map { SearchResultAnnotation(mapItem: $0) }
        searchResultAnnotations = annotations

        // 첫 번째 마커를 addAnnotations 전에 포커스 설정 (viewFor에서 색상 반영)
        annotations.first?.isFocused = true
        mapView.addAnnotations(annotations)

        if let first = annotations.first {
            fitAnnotations(annotations)
            mapView.selectAnnotation(first, animated: false)
        }
    }

    func clearSearchResults() {
        mapView.removeAnnotations(searchResultAnnotations)
        searchResultAnnotations = []
    }

    func focusAnnotation(at index: Int) {
        guard index < searchResultAnnotations.count else { return }

        for annotation in searchResultAnnotations {
            annotation.isFocused = false
        }

        let selected = searchResultAnnotations[index]
        selected.isFocused = true

        for annotation in searchResultAnnotations {
            if let view = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                view.markerTintColor = annotation.isFocused ? Theme.Colors.primary : .systemGray
            }
        }

        mapView.selectAnnotation(selected, animated: true)

        let region = MKCoordinateRegion(
            center: selected.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mapView.setRegion(region, animated: true)
    }

    // MARK: - Public: Destination

    func showDestination(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?) {
        clearDestination()
        let annotation = DestinationAnnotation(coordinate: coordinate, title: title, subtitle: subtitle)
        destinationAnnotation = annotation
        mapView.addAnnotation(annotation)
    }

    func clearDestination() {
        if let annotation = destinationAnnotation {
            mapView.removeAnnotation(annotation)
        }
        destinationAnnotation = nil
    }

    // MARK: - Public: Routes

    func showRoutes(_ routes: [MKRoute], selectedIndex: Int = 0) {
        clearRoutes()

        for (index, route) in routes.enumerated().reversed() {
            let isPrimary = (index == selectedIndex)
            routeOverlays.append(route.polyline)
            routeIsPrimary[route.polyline] = isPrimary
            mapView.addOverlay(route.polyline, level: .aboveRoads)
        }

        if selectedIndex < routes.count {
            fitPolyline(routes[selectedIndex].polyline)
        }
    }

    func clearRoutes() {
        for overlay in routeOverlays {
            mapView.removeOverlay(overlay)
        }
        routeOverlays = []
        routeIsPrimary = [:]
    }

    func clearAll() {
        clearSearchResults()
        clearDestination()
        clearRoutes()
    }

    // MARK: - Public: Navigation Mode

    /// Configure map for turn-by-turn navigation (3D camera, disable compass)
    func configureForNavigation() {
        isNavigationMode = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false

        // Add pan gesture recognizer to detect user interaction
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMapPan(_:)))
        pan.delegate = self
        mapView.addGestureRecognizer(pan)
        panGestureRecognizer = pan
    }

    /// Restore map to standard mode (2D, custom compass button)
    func configureForStandard() {
        isNavigationMode = false
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true

        // Remove navigation pan gesture
        if let pan = panGestureRecognizer {
            mapView.removeGestureRecognizer(pan)
            panGestureRecognizer = nil
        }

        // Reset camera to 2D
        let camera = MKMapCamera()
        camera.pitch = 0
        camera.heading = 0
        mapView.setCamera(camera, animated: false)
    }

    /// Apply a camera directly (used by interpolation system)
    func applyCamera(_ camera: MKMapCamera, animated: Bool) {
        mapView.setCamera(camera, animated: animated)
    }

    /// Show a single route for navigation (replaces any existing routes)
    func showSingleRoute(_ route: MKRoute) {
        clearRoutes()
        clearNavigationRoute()

        navigationRouteOverlay = route.polyline
        routeIsPrimary[route.polyline] = true
        mapView.addOverlay(route.polyline, level: .aboveRoads)
    }

    /// Clear navigation-specific route overlay
    func clearNavigationRoute() {
        if let overlay = navigationRouteOverlay {
            mapView.removeOverlay(overlay)
            routeIsPrimary.removeValue(forKey: overlay)
        }
        navigationRouteOverlay = nil
    }

    // MARK: - Generic Overlay

    /// Add a generic polyline overlay to the map
    func addOverlay(_ polyline: MKPolyline) {
        mapView.addOverlay(polyline, level: .aboveRoads)
    }

    // MARK: - Debug Overlay

    private var debugOverlayView: DebugOverlayView?

    func showDebugOverlay() {
        guard debugOverlayView == nil else { return }
        let overlay = DebugOverlayView()
        overlay.bind(to: locationService)
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.sm),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.sm),
        ])

        debugOverlayView = overlay
    }

    func hideDebugOverlay() {
        debugOverlayView?.unbind()
        debugOverlayView?.removeFromSuperview()
        debugOverlayView = nil
    }

    // MARK: - Parking Guidance

    private var parkingEntryAnnotation: MKPointAnnotation?

    /// Configure map for parking guidance mode (3D buildings, high pitch)
    func configureForParkingGuidance() {
        mapView.showsBuildings = true
        mapView.isPitchEnabled = true
    }

    /// Set map camera directly
    func setCamera(_ camera: MKMapCamera, animated: Bool) {
        mapView.setCamera(camera, animated: animated)
    }

    /// Show a parking entry marker at the destination
    func showParkingEntryMarker(at coordinate: CLLocationCoordinate2D) {
        removeParkingEntryMarker()

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "주차 진입"
        mapView.addAnnotation(annotation)
        parkingEntryAnnotation = annotation
    }

    /// Remove the parking entry marker
    func removeParkingEntryMarker() {
        if let annotation = parkingEntryAnnotation {
            mapView.removeAnnotation(annotation)
            parkingEntryAnnotation = nil
        }
    }

    // MARK: - Public: Map Controls

    /// Called when the user tracking mode changes (including auto-reset by MapKit)
    var onTrackingModeChanged: ((MKUserTrackingMode) -> Void)?

    /// Cycle through MKUserTrackingMode: none → follow → followWithHeading → none
    @discardableResult
    func cycleUserTrackingMode() -> MKUserTrackingMode {
        let next: MKUserTrackingMode = switch mapView.userTrackingMode {
        case .none: .follow
        case .follow: .followWithHeading
        case .followWithHeading: .none
        @unknown default: .none
        }
        mapView.setUserTrackingMode(next, animated: true)
        return next
    }

    /// Toggle between standard and satellite (both with realistic 3D elevation)
    @discardableResult
    func cycleMapType() -> Bool {
        let isSatellite = mapView.preferredConfiguration is MKImageryMapConfiguration
        if isSatellite {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        } else {
            mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        }
        return !isSatellite
    }

    @objc private func handleMapPan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            onUserInteraction?()
        }
    }

    // MARK: - Private Helpers

    private func fitAnnotations(_ annotations: [MKAnnotation]) {
        var rect = MKMapRect.null
        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            rect = rect.union(pointRect)
        }

        let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }

    private func fitPolyline(_ polyline: MKPolyline) {
        let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: padding, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MapViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

        if let vehicleAnnotation = annotation as? VehicleAnnotation {
            let identifier = "Vehicle"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation

            let iconService = VehicleIconService.shared
            if let vehicleImage = iconService.currentVehicleImage(size: 28) {
                view.image = vehicleImage
            } else {
                view.image = UIImage(systemName: "circle.fill")?
                    .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12))
            }

            // Rotate annotation view based on heading
            let rotation = vehicleAnnotation.heading * .pi / 180.0
            view.transform = CGAffineTransform(rotationAngle: rotation)

            view.canShowCallout = false
            return view
        }

        if let searchResult = annotation as? SearchResultAnnotation {
            let identifier = "SearchResult"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = searchResult.isFocused ? Theme.Colors.primary : .systemGray
            view.glyphImage = UIImage(systemName: "mappin")
            view.animatesWhenAdded = true
            view.canShowCallout = true
            return view
        }

        if annotation is DestinationAnnotation {
            let identifier = "Destination"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = .systemRed
            view.glyphImage = UIImage(systemName: "flag.fill")
            view.animatesWhenAdded = true
            view.canShowCallout = true
            return view
        }

        return nil
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let isPrimary = routeIsPrimary[polyline] ?? false
            return RouteOverlayRenderer(polyline: polyline, isPrimary: isPrimary)
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        onTrackingModeChanged?(mode)
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        if let featureAnnotation = annotation as? MKMapFeatureAnnotation {
            mapView.deselectAnnotation(annotation, animated: true)
            let request = MKMapItemRequest(mapFeatureAnnotation: featureAnnotation)
            Task {
                guard let mapItem = try? await request.mapItem else { return }
                onPOISelected?(mapItem)
            }
            return
        }

        guard let searchAnnotation = annotation as? SearchResultAnnotation,
              let index = searchResultAnnotations.firstIndex(where: { $0 === searchAnnotation }) else {
            return
        }

        // 탭된 마커의 focus 상태 즉시 업데이트 (색상 변경)
        for ann in searchResultAnnotations {
            ann.isFocused = false
        }
        searchAnnotation.isFocused = true
        for ann in searchResultAnnotations {
            if let view = mapView.view(for: ann) as? MKMarkerAnnotationView {
                view.markerTintColor = ann.isFocused ? Theme.Colors.primary : .systemGray
            }
        }

        onAnnotationSelected?(index)
    }
}
