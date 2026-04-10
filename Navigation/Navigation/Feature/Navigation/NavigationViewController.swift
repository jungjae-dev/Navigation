import UIKit
import MapKit
import SwiftUI
import Combine

/// 주행 화면 (지도 + 아바타 + 폴리라인 + 카메라 + 전체 UI)
final class NavigationViewController: UIViewController {

    // MARK: - Properties

    private let mapView = MKMapView()
    private let vehicleAnnotation = MKPointAnnotation()
    private let interpolator = LocationInterpolator()

    private let route: Route
    private let transportMode: TransportMode
    private let destinationName: String?
    private var cancellables = Set<AnyCancellable>()
    private var displayLink: CADisplayLink?
    private var currentSpeed: CLLocationSpeed = 0
    private var isAutoTracking = true

    // 마커
    private var originAnnotation: MKPointAnnotation?
    private var destinationAnnotation: MKPointAnnotation?
    private var routeOverlay: MKPolyline?

    // 7초 자동 복귀 타이머
    private var autoTrackTimer: Timer?
    private let autoTrackTimeout: TimeInterval = 7.0

    // SwiftUI Hosting Controllers
    private var bannerHostingController: UIHostingController<ManeuverBannerView>?
    private var bottomBarHostingController: UIHostingController<NavigationBottomBar>?
    private var speedometerHostingController: UIHostingController<SpeedometerView>?
    private var arrivalHostingController: UIHostingController<ArrivalPopupView>?

    // UI 요소
    private let recenterButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private var isMuted = false
    private let gpsStatusIcon = UIImageView()
    private let rerouteBannerView = UIView()
    private let rerouteBannerLabel = UILabel()

    // 포맷터 (재사용)
    private let etaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 주행 종료 콜백
    var onDismiss: (() -> Void)?

    /// 현재 guide
    private var currentGuide: NavigationGuide?
    private var hasShownArrival = false

    // MARK: - Init

    init(route: Route, transportMode: TransportMode, destinationName: String? = nil) {
        self.route = route
        self.transportMode = transportMode
        self.destinationName = destinationName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)

        setupMapView()
        setupRouteOverlay()
        setupMarkers()
        setupVehicleAnnotation()
        setupBanner()
        setupBottomBar()
        setupSpeedometer()
        setupRecenterButton()
        setupMuteButton()
        setupGPSStatusIcon()
        setupRerouteBanner()
        setupGestureDetection()
        startDisplayLink()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        interpolator.setTarget(guide.matchedPosition, heading: guide.heading)

        updateBanner(guide)
        updateBottomBar(guide)
        updateSpeedometer(guide)
        updateGPSStatus(guide)
        updateRerouteBanner(guide)

        if guide.state == .arrived && !hasShownArrival {
            hasShownArrival = true
            showArrivalPopup()
        }
    }

    // MARK: - Setup: Map

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

    private func setupRouteOverlay() {
        let coords = route.polylineCoordinates
        guard coords.count >= 2 else { return }
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        mapView.addOverlay(polyline, level: .aboveRoads)
        routeOverlay = polyline

        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 120, left: 40, bottom: 100, right: 40),
            animated: false
        )
    }

    private func setupMarkers() {
        if let first = route.polylineCoordinates.first {
            let origin = MKPointAnnotation()
            origin.coordinate = first
            origin.title = "출발"
            mapView.addAnnotation(origin)
            originAnnotation = origin
        }
        if let last = route.polylineCoordinates.last {
            let dest = MKPointAnnotation()
            dest.coordinate = last
            dest.title = "도착"
            mapView.addAnnotation(dest)
            destinationAnnotation = dest
        }
    }

    private func setupVehicleAnnotation() {
        if let first = route.polylineCoordinates.first {
            vehicleAnnotation.coordinate = first
        }
        vehicleAnnotation.title = "vehicle"
        mapView.addAnnotation(vehicleAnnotation)
    }

    // MARK: - Setup: Banner

    private func setupBanner() {
        let hosting = makeHostingController(ManeuverBannerView(currentManeuver: nil, nextManeuver: nil))

        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        bannerHostingController = hosting
    }

    private func updateBanner(_ guide: NavigationGuide) {
        bannerHostingController?.rootView = ManeuverBannerView(
            currentManeuver: guide.currentManeuver,
            nextManeuver: guide.nextManeuver
        )
        bannerHostingController?.view.invalidateIntrinsicContentSize()
        bannerHostingController?.view.setNeedsLayout()
        bannerHostingController?.view.layoutIfNeeded()
    }

    // MARK: - Setup: Bottom Bar

    private func setupBottomBar() {
        let bar = NavigationBottomBar(
            destinationName: destinationName, eta: "--:--",
            remainingDistance: "--", remainingTime: "--",
            onEndNavigation: { [weak self] in self?.onDismiss?() }
        )
        let hosting = makeHostingController(bar)

        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        bottomBarHostingController = hosting
    }

    private func updateBottomBar(_ guide: NavigationGuide) {
        let isRerouting = guide.state == .rerouting
        bottomBarHostingController?.rootView = NavigationBottomBar(
            destinationName: destinationName,
            eta: isRerouting ? "--:--" : etaFormatter.string(from: guide.eta),
            remainingDistance: isRerouting ? "--" : formatDistance(guide.remainingDistance),
            remainingTime: isRerouting ? "--" : formatTime(guide.remainingTime),
            onEndNavigation: { [weak self] in self?.onDismiss?() }
        )
    }

    // MARK: - Setup: Speedometer

    private func setupSpeedometer() {
        let hosting = makeHostingController(SpeedometerView(speed: 0))

        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hosting.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
        ])
        speedometerHostingController = hosting
    }

    private func updateSpeedometer(_ guide: NavigationGuide) {
        speedometerHostingController?.rootView = SpeedometerView(speed: guide.speed)
    }

    // MARK: - Setup: Recenter Button

    private func setupRecenterButton() {
        recenterButton.setImage(
            UIImage(systemName: "location.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            ), for: .normal
        )
        configureFloatingButton(recenterButton)
        recenterButton.isHidden = true
        recenterButton.addTarget(self, action: #selector(recenterTapped), for: .touchUpInside)

        view.addSubview(recenterButton)
        NSLayoutConstraint.activate([
            recenterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recenterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -150),
            recenterButton.widthAnchor.constraint(equalToConstant: 44),
            recenterButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func recenterTapped() { enableAutoTracking() }

    // MARK: - Setup: Mute Button

    private func setupMuteButton() {
        updateMuteButtonIcon()
        configureFloatingButton(muteButton)
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)

        view.addSubview(muteButton)
        NSLayoutConstraint.activate([
            muteButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            muteButton.bottomAnchor.constraint(equalTo: recenterButton.topAnchor, constant: -12),
            muteButton.widthAnchor.constraint(equalToConstant: 44),
            muteButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func muteTapped() {
        isMuted.toggle()
        updateMuteButtonIcon()
    }

    private func updateMuteButtonIcon() {
        let iconName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.setImage(
            UIImage(systemName: iconName)?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            ), for: .normal
        )
        muteButton.tintColor = isMuted ? .systemGray : .systemBlue
    }

    // MARK: - Setup: GPS Status Icon

    private func setupGPSStatusIcon() {
        gpsStatusIcon.image = UIImage(systemName: "antenna.radiowaves.left.and.right.slash")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        gpsStatusIcon.tintColor = .systemOrange
        gpsStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        gpsStatusIcon.isHidden = true

        view.addSubview(gpsStatusIcon)
        NSLayoutConstraint.activate([
            gpsStatusIcon.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            gpsStatusIcon.bottomAnchor.constraint(equalTo: muteButton.topAnchor, constant: -12),
            gpsStatusIcon.widthAnchor.constraint(equalToConstant: 24),
            gpsStatusIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func updateGPSStatus(_ guide: NavigationGuide) {
        gpsStatusIcon.isHidden = guide.isGPSValid
    }

    // MARK: - Setup: Reroute Banner

    private func setupRerouteBanner() {
        rerouteBannerView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.9)
        rerouteBannerView.translatesAutoresizingMaskIntoConstraints = false
        rerouteBannerView.isHidden = true
        rerouteBannerView.layer.cornerRadius = 8

        rerouteBannerLabel.text = "🔄 경로를 재탐색 중입니다..."
        rerouteBannerLabel.textAlignment = .center
        rerouteBannerLabel.font = .systemFont(ofSize: 15, weight: .medium)
        rerouteBannerLabel.translatesAutoresizingMaskIntoConstraints = false

        rerouteBannerView.addSubview(rerouteBannerLabel)
        view.addSubview(rerouteBannerView)

        NSLayoutConstraint.activate([
            rerouteBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 120),
            rerouteBannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            rerouteBannerView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            rerouteBannerView.heightAnchor.constraint(equalToConstant: 36),
            rerouteBannerLabel.centerXAnchor.constraint(equalTo: rerouteBannerView.centerXAnchor),
            rerouteBannerLabel.centerYAnchor.constraint(equalTo: rerouteBannerView.centerYAnchor),
        ])
    }

    private func updateRerouteBanner(_ guide: NavigationGuide) {
        rerouteBannerView.isHidden = guide.state != .rerouting
    }

    // MARK: - Arrival Popup

    private func showArrivalPopup() {
        let hosting = UIHostingController(rootView: ArrivalPopupView { [weak self] in
            self?.dismissArrivalPopup()
            self?.onDismiss?()
        })
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hosting.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hosting.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        arrivalHostingController = hosting
    }

    private func dismissArrivalPopup() {
        arrivalHostingController?.view.removeFromSuperview()
        arrivalHostingController?.removeFromParent()
        arrivalHostingController = nil
    }

    // MARK: - Gesture Detection

    private func setupGestureDetection() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMapGesture))
        pan.delegate = self
        mapView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleMapGesture))
        pinch.delegate = self
        mapView.addGestureRecognizer(pinch)
    }

    @objc private func handleMapGesture(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began { disableAutoTracking() }
    }

    // MARK: - Auto Tracking

    private func disableAutoTracking() {
        isAutoTracking = false
        recenterButton.isHidden = false
        resetAutoTrackTimer()
    }

    private func enableAutoTracking() {
        isAutoTracking = true
        recenterButton.isHidden = true
        autoTrackTimer?.invalidate()
        autoTrackTimer = nil
    }

    private func resetAutoTrackTimer() {
        autoTrackTimer?.invalidate()
        autoTrackTimer = Timer.scheduledTimer(withTimeInterval: autoTrackTimeout, repeats: false) { [weak self] _ in
            self?.enableAutoTracking()
        }
    }

    // MARK: - Display Link

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
        vehicleAnnotation.coordinate = result.coordinate

        if isAutoTracking {
            mapView.camera = NavigationCameraHelper.makeCamera(
                center: result.coordinate,
                heading: result.heading,
                speed: currentSpeed,
                mode: transportMode
            )
        }
    }

    // MARK: - Helpers

    /// SwiftUI 뷰를 UIHostingController로 래핑 (공통 설정)
    private func makeHostingController<V: View>(_ rootView: V) -> UIHostingController<V> {
        let hosting = UIHostingController(rootView: rootView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        addChild(hosting)
        hosting.didMove(toParent: self)
        return hosting
    }

    /// 플로팅 버튼 공통 스타일
    private func configureFloatingButton(_ button: UIButton) {
        button.backgroundColor = .systemBackground
        button.tintColor = .systemBlue
        button.layer.cornerRadius = 22
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.15
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 { return "\(totalMinutes)분" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(minutes)분"
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
            let id = "vehicle"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.image = UIImage(systemName: "location.north.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            view.canShowCallout = false
            return view
        }

        if annotation === originAnnotation {
            let id = "origin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            (view as? MKMarkerAnnotationView)?.markerTintColor = .systemGreen
            view.annotation = annotation
            return view
        }

        if annotation === destinationAnnotation {
            let id = "destination"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
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
    ) -> Bool { true }
}
