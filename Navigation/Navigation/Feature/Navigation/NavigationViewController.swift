import UIKit
import MapKit
import Combine

/// 주행 화면 (Step 8: 기본 — 지도 + 아바타 + 폴리라인 + 카메라)
/// Step 9에서 ManeuverBanner, BottomBar 등 전체 UI 추가 예정
final class NavigationViewController: UIViewController {

    // MARK: - Properties

    private let mapView = MKMapView()
    private let vehicleAnnotation = MKPointAnnotation()
    private let interpolator = LocationInterpolator()

    private let route: Route
    private let transportMode: TransportMode
    private var cancellables = Set<AnyCancellable>()
    private var displayLink: CADisplayLink?
    private var currentSpeed: CLLocationSpeed = 0
    private var isAutoTracking = true

    // 출발지/목적지 마커
    private var originAnnotation: MKPointAnnotation?
    private var destinationAnnotation: MKPointAnnotation?

    // 경로 오버레이
    private var routeOverlay: MKPolyline?

    // 7초 자동 복귀 타이머
    private var autoTrackTimer: Timer?
    private let autoTrackTimeout: TimeInterval = 7.0

    /// 주행 종료 콜백
    var onDismiss: (() -> Void)?

    /// 현재 guide (백그라운드 복귀 시 사용)
    private var currentGuide: NavigationGuide?

    // MARK: - Init

    init(route: Route, transportMode: TransportMode) {
        self.route = route
        self.transportMode = transportMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)

        setupMapView()
        setupRouteOverlay()
        setupMarkers()
        setupVehicleAnnotation()
        setupGestureDetection()
        startDisplayLink()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 백그라운드 복귀 시 보간기 리셋 (점프 방지)
        if let guide = currentGuide {
            interpolator.resetTo(guide.matchedPosition, guide.heading)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDisplayLink()
    }

    // MARK: - Bind Engine

    func bind(to guidePublisher: CurrentValueSubject<NavigationGuide?, Never>) {
        guidePublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] guide in
                self?.handleGuide(guide)
            }
            .store(in: &cancellables)
    }

    // MARK: - Handle Guide

    private func handleGuide(_ guide: NavigationGuide) {
        currentGuide = guide
        currentSpeed = guide.speed

        // 보간기에 새 타겟 전달
        interpolator.setTarget(guide.matchedPosition, heading: guide.heading)

        // 도착 처리
        if guide.state == .arrived {
            handleArrival()
        }
    }

    // MARK: - Setup Map

    private func setupMapView() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.pointOfInterestFilter = .excludingAll

        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Route Overlay

    private func setupRouteOverlay() {
        let coords = route.polylineCoordinates
        guard coords.count >= 2 else { return }

        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        mapView.addOverlay(polyline, level: .aboveRoads)
        routeOverlay = polyline

        // 초기에 전체 경로 보기
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40),
            animated: false
        )
    }

    // MARK: - Markers

    private func setupMarkers() {
        // 출발지
        if let firstCoord = route.polylineCoordinates.first {
            let origin = MKPointAnnotation()
            origin.coordinate = firstCoord
            origin.title = "출발"
            mapView.addAnnotation(origin)
            originAnnotation = origin
        }

        // 목적지
        if let lastCoord = route.polylineCoordinates.last {
            let dest = MKPointAnnotation()
            dest.coordinate = lastCoord
            dest.title = "도착"
            mapView.addAnnotation(dest)
            destinationAnnotation = dest
        }
    }

    // MARK: - Vehicle Annotation

    private func setupVehicleAnnotation() {
        if let firstCoord = route.polylineCoordinates.first {
            vehicleAnnotation.coordinate = firstCoord
        }
        vehicleAnnotation.title = "vehicle"
        mapView.addAnnotation(vehicleAnnotation)
    }

    // MARK: - Gesture Detection (지도 조작 감지)

    private func setupGestureDetection() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleMapGesture))
        panGesture.delegate = self
        mapView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleMapGesture))
        pinchGesture.delegate = self
        mapView.addGestureRecognizer(pinchGesture)
    }

    @objc private func handleMapGesture(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            disableAutoTracking()
        }
    }

    // MARK: - Auto Tracking

    private func disableAutoTracking() {
        isAutoTracking = false
        resetAutoTrackTimer()
    }

    private func enableAutoTracking() {
        isAutoTracking = true
        autoTrackTimer?.invalidate()
        autoTrackTimer = nil
    }

    private func resetAutoTrackTimer() {
        autoTrackTimer?.invalidate()
        autoTrackTimer = Timer.scheduledTimer(withTimeInterval: autoTrackTimeout, repeats: false) { [weak self] _ in
            self?.enableAutoTracking()
        }
    }

    // MARK: - Display Link (60fps)

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        let result = interpolator.interpolate()

        // 아바타 위치 업데이트
        vehicleAnnotation.coordinate = result.coordinate

        // 카메라 추적
        if isAutoTracking {
            let camera = NavigationCameraHelper.makeCamera(
                center: result.coordinate,
                heading: result.heading,
                speed: currentSpeed,
                mode: transportMode
            )
            mapView.camera = camera
        }
    }

    // MARK: - Arrival

    private func handleArrival() {
        // Step 9에서 ArrivalPopup으로 교체 예정
        // 현재는 3초 후 자동 종료
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.onDismiss?()
        }
    }

    // MARK: - Cleanup

    deinit {
        stopDisplayLink()
        autoTrackTimer?.invalidate()
    }
}

// MARK: - MKMapViewDelegate

extension NavigationViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        if annotation === vehicleAnnotation {
            let identifier = "vehicle"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.image = UIImage(systemName: "location.north.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            view.canShowCallout = false
            return view
        }

        if annotation === originAnnotation {
            let identifier = "origin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            (view as? MKMarkerAnnotationView)?.markerTintColor = .systemGreen
            view.annotation = annotation
            return view
        }

        if annotation === destinationAnnotation {
            let identifier = "destination"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            (view as? MKMarkerAnnotationView)?.markerTintColor = .systemRed
            view.annotation = annotation
            return view
        }

        return nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension NavigationViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true  // MKMapView 제스처와 동시 인식
    }
}
