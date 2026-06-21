import UIKit
import MapKit
import Combine
import OSLog

private let bikeMapLogger = Logger(subsystem: "nav.bike", category: "Map")
private let mapTapLogger = Logger(subsystem: "nav.map", category: "Tap")

final class MapViewController: UIViewController {

    // MARK: - Properties

    let mapView = TouchObservableMapView()
    private let locationService: LocationService
    private lazy var userLocationPresenter = UserLocationPresenter(
        mapView: mapView,
        headingSource: .compass,
        locationService: locationService
    )
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Search & Route State

    private var searchResultAnnotations: [SearchResultAnnotation] = []
    private var destinationAnnotation: DestinationAnnotation?
    private var poiAnnotation: POIAnnotation?
    private var routeOverlays: [MKPolyline] = []
    private var routeIsPrimary: [MKPolyline: Bool] = [:]

    /// Callback when a search result marker is tapped. Returns the index.
    var onAnnotationSelected: ((Int) -> Void)?

    /// Callback when a built-in POI is tapped.
    var onPOISelected: ((Place) -> Void)?

    /// Callback when a 따릉이 station marker is tapped.
    var onBikeStationSelected: ((BikeStation) -> Void)?
    var onBusStopSelected: ((BusStop) -> Void)?

    /// Callback when an empty area of the map is tapped (no annotation / no built-in feature).
    var onEmptyMapTapped: (() -> Void)?

    /// 롱프레스로 핀을 찍었을 때 (동네 인사이트 진입)
    var onLongPressDropped: ((CLLocationCoordinate2D) -> Void)?
    private var insightPin: MKPointAnnotation?

    /// 현재 표시 중인 따릉이 정류소 annotations
    private var bikeAnnotations: [BikeAnnotation] = []
    /// 따릉이 표시 ON/OFF (외부에서 설정)
    private var bikeLayerEnabled: Bool = false
    /// 따릉이 마커를 표시하는 최대 latitudeDelta 임계값
    /// 이 값보다 크면 (= 더 줌 아웃이면) 마커를 숨김
    private static let bikeMaxLatitudeDelta: Double = 0.05

    /// 빈 곳 탭 판정 디바운스 — 후속 didSelect 가 따라오면 취소되도록 짧게 둠
    private static let emptyTapCloseDebounce: TimeInterval = 0.05

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
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.selectableMapFeatures = [.pointsOfInterest]

        userLocationPresenter.attach()
        userLocationPresenter.onTrackingModeChanged = { [weak self] mode in
            self?.onTrackingModeChanged?(mode)
        }
        mapView.onUserTouch = { [weak self] in
            self?.userLocationPresenter.userDidInteractWithMap()
        }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)
    }

    // MARK: - Insight Long Press

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isNavigationMode else { return }
        let point = gesture.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        print("[Insight] 1. longPress at \(coordinate.latitude),\(coordinate.longitude)")
        dropInsightPin(at: coordinate)
        onLongPressDropped?(coordinate)
    }

    /// 인사이트 핀 표시(이전 핀 교체)
    func dropInsightPin(at coordinate: CLLocationCoordinate2D) {
        clearInsightPin()
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        mapView.addAnnotation(pin)
        insightPin = pin
    }

    func clearInsightPin() {
        if let pin = insightPin {
            mapView.removeAnnotation(pin)
            insightPin = nil
        }
    }

    private var pendingEmptyTapCheck: DispatchWorkItem?

    // MARK: - Binding

    // MARK: - Initial Location

    /// 인셋 설정 후 호출하여 첫 위치로 지도 이동
    func moveToInitialLocation() {
        locationService.rawLocationPublisher
            .compactMap { $0 }
            .first()
            .sink { [weak self] location in
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                self?.mapView.setRegion(region, animated: false)
            }
            .store(in: &cancellables)
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

    func showSearchResults(_ places: [Place]) {
        addSearchResults(places)
        fitToSearchResults()
    }

    func addSearchResults(_ places: [Place]) {
        print("[MapVC] addSearchResults called with \(places.count) places")
        clearSearchResults()

        let annotations = places.map { SearchResultAnnotation(place: $0) }
        searchResultAnnotations = annotations

        // 첫 번째 마커를 addAnnotations 전에 포커스 설정 (viewFor에서 색상 반영)
        annotations.first?.isFocused = true
        mapView.addAnnotations(annotations)

        if let first = annotations.first {
            mapView.selectAnnotation(first, animated: false)
        }
    }

    func appendSearchResults(_ places: [Place]) {
        let annotations = places.map { SearchResultAnnotation(place: $0) }
        searchResultAnnotations.append(contentsOf: annotations)
        mapView.addAnnotations(annotations)
    }

    func fitToSearchResults() {
        guard !searchResultAnnotations.isEmpty else {
            print("[MapVC] fitToSearchResults: no annotations")
            return
        }
        print("[MapVC] fitToSearchResults: \(searchResultAnnotations.count) annotations")
        regionChangeSuppressionEnd = Date().addingTimeInterval(1.0)
        fitAnnotations(searchResultAnnotations)
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

        regionChangeSuppressionEnd = Date().addingTimeInterval(1.0)
        mapView.selectAnnotation(selected, animated: true)
        mapView.setCenter(selected.coordinate, animated: true)
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

    // MARK: - Public: POI Marker

    func showPOIMarker(for place: Place, zoomIn: Bool = false) {
        clearPOIMarker()
        let annotation = POIAnnotation(place: place)
        poiAnnotation = annotation
        mapView.addAnnotation(annotation)
        mapView.selectAnnotation(annotation, animated: true)

        if zoomIn {
            moveToLocation(annotation.coordinate)
        } else {
            mapView.setCenter(annotation.coordinate, animated: true)
        }
    }

    func clearPOIMarker() {
        if let annotation = poiAnnotation {
            mapView.removeAnnotation(annotation)
        }
        poiAnnotation = nil
    }

    // MARK: - Public: Routes

    func showRoutes(_ routes: [Route], selectedIndex: Int = 0) {
        clearRoutes()

        for (index, route) in routes.enumerated().reversed() {
            let isPrimary = (index == selectedIndex)
            let polyline = route.mkPolyline
            routeOverlays.append(polyline)
            routeIsPrimary[polyline] = isPrimary
            mapView.addOverlay(polyline, level: .aboveRoads)
        }

        if selectedIndex < routes.count {
            fitPolyline(routes[selectedIndex].mkPolyline)
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
        clearPOIMarker()
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

        // Reset camera to 2D — keep current center & altitude
        let camera = mapView.camera.copy() as! MKMapCamera
        camera.pitch = 0
        camera.heading = 0
        mapView.setCamera(camera, animated: false)
    }

    /// Apply a camera directly (used by interpolation system)
    func applyCamera(_ camera: MKMapCamera, animated: Bool) {
        mapView.setCamera(camera, animated: animated)
    }

    /// Show a single route for navigation (replaces any existing routes)
    func showSingleRoute(_ route: Route) {
        clearRoutes()
        clearNavigationRoute()

        let polyline = route.mkPolyline
        navigationRouteOverlay = polyline
        routeIsPrimary[polyline] = true
        mapView.addOverlay(polyline, level: .aboveRoads)
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

    /// Called when the user tracking mode changes
    var onTrackingModeChanged: ((UserLocationPresenter.TrackingMode) -> Void)?

    /// Called when the map region changes by user interaction
    var onRegionChanged: (() -> Void)?
    private var regionChangeSuppressionEnd: Date = .distantPast

    /// Cycle through tracking mode: none → follow → followWithHeading → none
    @discardableResult
    func cycleUserTrackingMode() -> UserLocationPresenter.TrackingMode {
        userLocationPresenter.cycleTrackingMode()
    }

    /// Tracking mode 직접 지정
    func setUserTrackingMode(_ mode: UserLocationPresenter.TrackingMode) {
        userLocationPresenter.setTrackingMode(mode)
    }

    var trackingMode: UserLocationPresenter.TrackingMode {
        userLocationPresenter.trackingMode
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

    // MARK: - Bike Stations

    /// 따릉이 정류소 데이터 설정 (실제 표시는 줌 레벨에 따라 결정)
    /// - 빈 배열을 전달하면 모두 제거
    func setBikeStations(_ stations: [BikeStation]) {
        // 캐시된 annotation 모두 제거 후 새 인스턴스 생성
        if !bikeAnnotations.isEmpty {
            mapView.removeAnnotations(bikeAnnotations)
        }
        bikeAnnotations = stations.map { BikeAnnotation(station: $0) }
        bikeLayerEnabled = !stations.isEmpty
        bikeMapLogger.info("setBikeStations: \(self.bikeAnnotations.count, privacy: .public)개 정류소 로드")
        // 현재 줌에 맞게 표시 결정
        updateBikeAnnotationsVisibility()
    }

    /// 따릉이 정류소 annotations 모두 제거
    func clearBikeStations() {
        bikeLayerEnabled = false
        guard !bikeAnnotations.isEmpty else { return }
        let displayed = mapView.annotations.filter { $0 is BikeAnnotation }
        mapView.removeAnnotations(displayed)
        bikeAnnotations = []
        bikeMapLogger.info("clearBikeStations")
    }

    /// 따릉이 정류소 포커스 — 지도 이동 + 마커 선택 (POI 의 showPOIMarker 와 유사)
    func focusBikeStation(_ station: BikeStation, zoomIn: Bool = false) {
        if let annotation = bikeAnnotations.first(where: { $0.station.stationId == station.stationId }) {
            mapView.selectAnnotation(annotation, animated: true)
        }
        if zoomIn {
            moveToLocation(station.coordinate)
        } else {
            mapView.setCenter(station.coordinate, animated: true)
        }
    }

    /// 따릉이 정류소 선택 해제
    func deselectAllBikeStations() {
        for annotation in mapView.selectedAnnotations where annotation is BikeAnnotation {
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }

    /// 버스 정류소 선택 해제
    func deselectAllBusStops() {
        for annotation in mapView.selectedAnnotations where annotation is BusStopAnnotation {
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }

    /// 현재 줌 레벨에 따라 따릉이 마커 표시/숨김 갱신
    private func updateBikeAnnotationsVisibility() {
        guard !routeFocusMode, bikeLayerEnabled, !bikeAnnotations.isEmpty else { return }

        let latDelta = mapView.region.span.latitudeDelta
        let shouldShow = latDelta <= Self.bikeMaxLatitudeDelta

        let displayedBikes = mapView.annotations.filter { $0 is BikeAnnotation }
        let isShowing = !displayedBikes.isEmpty

        if shouldShow && !isShowing {
            mapView.addAnnotations(bikeAnnotations)
            bikeMapLogger.info("[ZOOM] latΔ=\(String(format: "%.4f", latDelta), privacy: .public) → 마커 표시 (\(self.bikeAnnotations.count, privacy: .public)개)")
        } else if !shouldShow && isShowing {
            mapView.removeAnnotations(displayedBikes)
            bikeMapLogger.info("[ZOOM] latΔ=\(String(format: "%.4f", latDelta), privacy: .public) → 마커 숨김 (임계값 \(Self.bikeMaxLatitudeDelta, privacy: .public) 초과)")
        }
    }

    // MARK: - Transit Route Polyline

    private var transitRouteOverlays: [MKPolyline] = []
    private var transitPrimaryFlags: [MKPolyline: Bool] = [:]

    /// 단일 방향(폴백) 표시 — 방향 데이터가 없거나 순환 노선일 때
    func showBusRoutePolyline(_ coords: [CLLocationCoordinate2D]) {
        showBusRoutePolyline(primary: coords, opposite: [])
    }

    /// 상/하행 구분 표시.
    /// - primary: 선택 정류소가 포함된 방향 (짙은 색)
    /// - opposite: 반대 방향 구간들 (옅은 색). 비연속 구간 대비 배열의 배열
    func showBusRoutePolyline(primary: [CLLocationCoordinate2D], opposite: [[CLLocationCoordinate2D]]) {
        clearTransitPolyline()
        // 반대 방향을 먼저(아래) 그리고 선택 방향을 나중(위)에 그려 가독성 확보
        for segment in opposite {
            addTransitSegment(segment, isPrimary: false)
        }
        addTransitSegment(primary, isPrimary: true)
    }

    private func addTransitSegment(_ coords: [CLLocationCoordinate2D], isPrimary: Bool) {
        guard coords.count >= 2 else { return }
        var mutable = coords
        let polyline = MKPolyline(coordinates: &mutable, count: mutable.count)
        polyline.title = "transit_route"
        transitPrimaryFlags[polyline] = isPrimary
        transitRouteOverlays.append(polyline)
        mapView.addOverlay(polyline, level: .aboveRoads)
    }

    func clearTransitPolyline() {
        guard !transitRouteOverlays.isEmpty else { return }
        mapView.removeOverlays(transitRouteOverlays)
        transitPrimaryFlags.removeAll()
        transitRouteOverlays = []
    }

    // MARK: - Bus Stops

    private var busStopAnnotations: [BusStopAnnotation] = []
    private var busLayerEnabled: Bool = false
    private static let busMaxLatitudeDelta: Double = 0.03

    func setBusStops(_ stops: [BusStop]) {
        if !busStopAnnotations.isEmpty {
            mapView.removeAnnotations(busStopAnnotations)
        }
        busStopAnnotations = stops.map { BusStopAnnotation(busStop: $0) }
        busLayerEnabled = !stops.isEmpty
        updateBusAnnotationsVisibility()
    }

    func clearBusStops() {
        busLayerEnabled = false
        guard !busStopAnnotations.isEmpty else { return }
        let displayed = mapView.annotations.filter { $0 is BusStopAnnotation }
        mapView.removeAnnotations(displayed)
        busStopAnnotations = []
    }

    private func updateBusAnnotationsVisibility() {
        guard !routeFocusMode, busLayerEnabled, !busStopAnnotations.isEmpty else { return }
        let latDelta = mapView.region.span.latitudeDelta
        let shouldShow = latDelta <= Self.busMaxLatitudeDelta
        let displayed = Set(mapView.annotations.compactMap { $0 as? BusStopAnnotation })
        if shouldShow {
            // 이미 표시된 것 제외하고 누락분만 추가 (포커스 중 남겨둔 마커와 중복 방지)
            let missing = busStopAnnotations.filter { !displayed.contains($0) }
            if !missing.isEmpty { mapView.addAnnotations(missing) }
        } else if !displayed.isEmpty {
            mapView.removeAnnotations(Array(displayed))
        }
    }

    // MARK: - Route Focus Mode

    /// 노선 정보 보기 중 — 선택 정류장 외 버스/따릉이 마커를 숨겨 노선만 부각
    private var routeFocusMode = false

    func enterRouteFocus(keepingStopArsId arsId: String?) {
        routeFocusMode = true
        // 버스 마커: 선택 정류장만 남기고 제거
        let busToRemove = mapView.annotations
            .compactMap { $0 as? BusStopAnnotation }
            .filter { $0.busStop.arsId != arsId }
        if !busToRemove.isEmpty { mapView.removeAnnotations(busToRemove) }
        // 따릉이 마커 전부 숨김
        let bikeDisplayed = mapView.annotations.filter { $0 is BikeAnnotation }
        if !bikeDisplayed.isEmpty { mapView.removeAnnotations(bikeDisplayed) }
    }

    func exitRouteFocus() {
        guard routeFocusMode else { return }
        routeFocusMode = false
        clearBusVehicles()
        clearRouteStops()
        // 현재 줌/레이어 상태대로 마커 복원
        updateBusAnnotationsVisibility()
        updateBikeAnnotationsVisibility()
    }

    // MARK: - Route Stops (노선 경유 정류소)

    private var routeStopAnnotations: [BusStopAnnotation] = []

    /// 노선 경유 정류소를 마커로 표시 (선택 정류장은 중복 방지 위해 제외)
    func showRouteStops(_ stops: [BusRouteStop], excludingArsId excludeArsId: String?) {
        clearRouteStops()
        let annotations = stops.compactMap { stop -> BusStopAnnotation? in
            if let ex = excludeArsId, stop.arsId == ex { return nil }
            let busStop = BusStop(stId: stop.stationId, arsId: stop.arsId, name: stop.name, lat: stop.lat, lng: stop.lng)
            return BusStopAnnotation(busStop: busStop)
        }
        routeStopAnnotations = annotations
        if !annotations.isEmpty { mapView.addAnnotations(annotations) }
    }

    func clearRouteStops() {
        guard !routeStopAnnotations.isEmpty else { return }
        mapView.removeAnnotations(routeStopAnnotations)
        routeStopAnnotations = []
    }

    // MARK: - Bus Vehicles (실시간 운행 위치)

    private var busVehicleAnnotations: [BusVehicleAnnotation] = []

    func showBusVehicles(_ vehicles: [BusVehicle]) {
        clearBusVehicles()
        guard !vehicles.isEmpty else { return }
        busVehicleAnnotations = vehicles.map { BusVehicleAnnotation(vehicle: $0) }
        mapView.addAnnotations(busVehicleAnnotations)
    }

    func clearBusVehicles() {
        guard !busVehicleAnnotations.isEmpty else { return }
        mapView.removeAnnotations(busVehicleAnnotations)
        busVehicleAnnotations = []
    }


    // MARK: - Private Helpers

    private func fitAnnotations(_ annotations: [MKAnnotation]) {
        var rect = MKMapRect.null
        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            rect = rect.union(pointRect)
        }

        let inset: CGFloat = 40
        let margins = mapView.layoutMargins
        let padding = UIEdgeInsets(
            top: max(margins.top, inset),
            left: max(margins.left, inset),
            bottom: max(margins.bottom, inset),
            right: max(margins.right, inset)
        )
        print("[MapVC] fitAnnotations: rect=\(rect), padding=\(padding), mapFrame=\(mapView.frame), margins=\(margins)")
        print("[MapVC] fitAnnotations: currentRegion center=(\(mapView.region.center.latitude), \(mapView.region.center.longitude)) span=(\(mapView.region.span.latitudeDelta), \(mapView.region.span.longitudeDelta))")
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }

    private func fitPolyline(_ polyline: MKPolyline) {
        let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: padding, animated: true)
    }

    deinit {
        pendingEmptyTapCheck?.cancel()
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

        // 우리 user location annotation
        if let view = userLocationPresenter.makeAnnotationView(for: annotation) {
            return view
        }

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
            // 따릉이 마커와 겹쳐도 숨겨지지 않도록 collision 비활성
            view.displayPriority = .required
            view.collisionMode = .none
            return view
        }

        if let poi = annotation as? POIAnnotation {
            let identifier = "POI"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = Theme.Colors.primary
            view.glyphImage = UIImage(systemName: poi.glyphIconName)
            view.animatesWhenAdded = true
            view.canShowCallout = true
            view.displayPriority = .required
            view.collisionMode = .none
            return view
        }

        if annotation is BikeAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: BikeAnnotationView.reuseIdentifier) as? BikeAnnotationView
                ?? BikeAnnotationView(annotation: annotation, reuseIdentifier: BikeAnnotationView.reuseIdentifier)
            view.annotation = annotation
            return view
        }

        if annotation is BusStopAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: BusStopAnnotationView.reuseIdentifier) as? BusStopAnnotationView
                ?? BusStopAnnotationView(annotation: annotation, reuseIdentifier: BusStopAnnotationView.reuseIdentifier)
            view.annotation = annotation
            return view
        }

        if annotation is BusVehicleAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: BusVehicleAnnotationView.reuseIdentifier) as? BusVehicleAnnotationView
                ?? BusVehicleAnnotationView(annotation: annotation, reuseIdentifier: BusVehicleAnnotationView.reuseIdentifier)
            view.annotation = annotation
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
            // 대중교통 노선 폴리라인 — 방향 구분 + 진행방향 화살표
            if let title = polyline.title, title.hasPrefix("transit_route") {
                let isPrimary = transitPrimaryFlags[polyline] ?? true
                return TransitRouteRenderer(polyline: polyline, isPrimary: isPrimary)
            }
            let isPrimary = routeIsPrimary[polyline] ?? false
            return RouteOverlayRenderer(polyline: polyline, isPrimary: isPrimary)
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard Date() > regionChangeSuppressionEnd else { return }
        onRegionChanged?()
        updateBikeAnnotationsVisibility()
        updateBusAnnotationsVisibility()
    }

    private func annotationKind(_ annotation: any MKAnnotation) -> String {
        if annotation is MKMapFeatureAnnotation { return "MKMapFeatureAnnotation" }
        if annotation is POIAnnotation { return "POIAnnotation" }
        if annotation is BikeAnnotation { return "BikeAnnotation" }
        if annotation is SearchResultAnnotation { return "SearchResultAnnotation" }
        return "Other"
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        mapTapLogger.debug("[MAP] didSelect \(self.annotationKind(annotation), privacy: .public) pendingClose=\(self.pendingEmptyTapCheck != nil, privacy: .public)")

        // annotation/feature 가 선택되었으므로 빈 곳 탭 디바운스 취소
        pendingEmptyTapCheck?.cancel()
        pendingEmptyTapCheck = nil

        if let bikeAnnotation = annotation as? BikeAnnotation {
            bikeMapLogger.info("✓ Bike station tapped: \(bikeAnnotation.station.stationId, privacy: .public) \(bikeAnnotation.station.stationName, privacy: .public)")
            onBikeStationSelected?(bikeAnnotation.station)
            return
        }

        if let busAnnotation = annotation as? BusStopAnnotation {
            onBusStopSelected?(busAnnotation.busStop)
            return
        }

        if let featureAnnotation = annotation as? MKMapFeatureAnnotation {
            mapView.deselectAnnotation(annotation, animated: true)
            let request = MKMapItemRequest(mapFeatureAnnotation: featureAnnotation)
            Task {
                guard let mapItem = try? await request.mapItem else { return }
                onPOISelected?(AppleModelConverter.place(from: mapItem))
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

        mapView.setCenter(searchAnnotation.coordinate, animated: true)
        onAnnotationSelected?(index)
    }

    func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
        let isOurs = annotation is POIAnnotation
            || annotation is BikeAnnotation
            || annotation is SearchResultAnnotation
        guard isOurs else {
            mapTapLogger.debug("[MAP] didDeselect \(self.annotationKind(annotation), privacy: .public) → 무시 (custom 아님)")
            return
        }
        mapTapLogger.debug("[MAP] didDeselect \(self.annotationKind(annotation), privacy: .public) → close 예약 (+50ms)")

        pendingEmptyTapCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEmptyTapCheck = nil
            guard self.mapView.selectedAnnotations.isEmpty else { return }
            mapTapLogger.info("[MAP] 빈 곳 탭 → 드로어 닫기")
            self.onEmptyMapTapped?()
        }
        pendingEmptyTapCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emptyTapCloseDebounce, execute: work)
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else { return nil }
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}
