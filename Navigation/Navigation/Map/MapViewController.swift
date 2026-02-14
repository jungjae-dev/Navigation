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
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.mapType = .standard
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.pointOfInterestFilter = .includingAll
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
        mapView.addAnnotations(annotations)

        if let first = annotations.first {
            first.isFocused = true
            fitAnnotations(annotations)
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

    // MARK: - Private Helpers

    private func fitAnnotations(_ annotations: [MKAnnotation]) {
        var rect = MKMapRect.null
        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            rect = rect.union(pointRect)
        }

        let padding = UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }

    private func fitPolyline(_ polyline: MKPolyline) {
        let padding = UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40)
        mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: padding, animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

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

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        guard let searchAnnotation = annotation as? SearchResultAnnotation,
              let index = searchResultAnnotations.firstIndex(where: { $0 === searchAnnotation }) else {
            return
        }
        onAnnotationSelected?(index)
    }
}
