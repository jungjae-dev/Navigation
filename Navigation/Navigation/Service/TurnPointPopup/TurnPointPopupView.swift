import UIKit
import MapKit
import Combine

/// A popup view showing a north-fixed 2D map of the upcoming turn point
final class TurnPointPopupView: UIView {

    // MARK: - UI

    private let mapView: MKMapView = {
        let map = MKMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        map.isUserInteractionEnabled = false
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.mapType = .standard
        map.pointOfInterestFilter = .excludingAll
        return map
    }()

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black
        view.layer.cornerRadius = Theme.CornerRadius.medium
        view.layer.masksToBounds = true
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        return view
    }()

    // MARK: - State

    private var vehicleAnnotation: VehicleAnnotation?
    private var routeOverlay: MKPolyline?
    private let mapDelegate = TurnPointMapDelegate()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(mapView)

        mapView.delegate = mapDelegate

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            mapView.topAnchor.constraint(equalTo: containerView.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        alpha = 0
    }

    // MARK: - Public

    func configure(with config: PopupConfig) {
        // Clear previous state
        if let overlay = routeOverlay {
            mapView.removeOverlay(overlay)
        }
        if let annotation = vehicleAnnotation {
            mapView.removeAnnotation(annotation)
        }

        // Add route overlay
        routeOverlay = config.routePolyline
        mapView.addOverlay(config.routePolyline, level: .aboveRoads)

        // Add vehicle annotation
        let vehicle = VehicleAnnotation(coordinate: config.vehicleCoordinate)
        vehicleAnnotation = vehicle
        mapView.addAnnotation(vehicle)

        // Set camera: north-fixed, 2D, centered on turn point
        let camera = MKMapCamera()
        camera.centerCoordinate = config.centerCoordinate
        camera.heading = 0 // North-fixed
        camera.pitch = 0 // 2D view
        camera.centerCoordinateDistance = 300 // Close zoom
        mapView.setCamera(camera, animated: false)

        // Fit to show both vehicle and turn point with padding
        fitToShowPoints(vehicle: config.vehicleCoordinate, turnPoint: config.centerCoordinate)
    }

    func updateVehiclePosition(_ coordinate: CLLocationCoordinate2D) {
        vehicleAnnotation?.updatePosition(coordinate)
    }

    func showAnimated() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }
    }

    func hideAnimated(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
        }, completion: { _ in
            completion?()
        })
    }

    // MARK: - Private

    private func fitToShowPoints(vehicle: CLLocationCoordinate2D, turnPoint: CLLocationCoordinate2D) {
        var rect = MKMapRect.null

        let vehiclePoint = MKMapPoint(vehicle)
        let turnPointPoint = MKMapPoint(turnPoint)

        let vehicleRect = MKMapRect(x: vehiclePoint.x, y: vehiclePoint.y, width: 0.1, height: 0.1)
        let turnRect = MKMapRect(x: turnPointPoint.x, y: turnPointPoint.y, width: 0.1, height: 0.1)

        rect = vehicleRect.union(turnRect)

        // Add 40% padding
        let dx = rect.size.width * 0.4
        let dy = rect.size.height * 0.4
        let paddedRect = MKMapRect(
            x: rect.origin.x - dx / 2,
            y: rect.origin.y - dy / 2,
            width: rect.size.width + dx,
            height: rect.size.height + dy
        )

        let padding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mapView.setVisibleMapRect(paddedRect, edgePadding: padding, animated: false)

        // Force north-up after fitting
        let currentCamera = mapView.camera
        currentCamera.heading = 0
        currentCamera.pitch = 0
        mapView.setCamera(currentCamera, animated: false)
    }
}

// MARK: - Turn Point Map Delegate

private final class TurnPointMapDelegate: NSObject, MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation is VehicleAnnotation {
            let identifier = "PopupVehicle"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.image = UIImage(systemName: "circle.fill")?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14))
            view.canShowCallout = false
            return view
        }
        return nil
    }
}
