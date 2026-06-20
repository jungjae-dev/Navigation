import UIKit
import MapKit
import Combine
import CoreLocation
import OSLog

private let coordLogger = Logger(subsystem: "nav.ui", category: "AppCoordinator")

final class AppCoordinator: NSObject, Coordinator {

    // MARK: - Coordinator

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []

    // MARK: - Properties

    private let window: UIWindow
    private let locationService: LocationService
    private var searchService: SearchProviding { LBSServiceProvider.shared.search }
    private var routeService: RouteProviding { LBSServiceProvider.shared.route }
    private let sessionManager = NavigationSessionManager.shared

    private var mapViewController: MapViewController!
    private var homeViewController: HomeViewController!
    private var homeViewModel: HomeViewModel!
    private var homeDrawerVC: HomeDrawerViewController?
    private var currentDrawer: SearchResultDrawerViewController?
    private var lastSearchQuery: String = ""
    /// POI / 따릉이 / 버스·지하철 통합 상세 시트
    private var mapItemDetailDrawer: MapItemDetailViewController?
    private let regionCodeService = RegionCodeService()
    private var routePreviewDrawer: RoutePreviewDrawerViewController?
    /// 버스/지하철 노선 드로어 (1개만 유지)
    private var transitRouteDrawer: UIViewController?
    private var cancellables = Set<AnyCancellable>()

    private var drawerManager: DrawerContainerManager {
        homeViewController.drawerManager
    }

    // MARK: - iPhone-only Navigation Services (stub — 새 엔진 구현 시 교체 예정)

    // MARK: - Navigation Map (ephemeral, created per session)

    private var navigationMapViewController: MapViewController?

    // MARK: - Virtual Drive

    /// 가상 주행 진행 중인 driver (안내 lifecycle에 종속)
    private var activeVirtualDriveDriver: VirtualDriveDriver?

    // MARK: - Init

    init(window: UIWindow) {
        self.window = window
        self.locationService = .shared
        self.navigationController = UINavigationController()
        self.navigationController.isNavigationBarHidden = true

        super.init()

        // "File 모드인데 파일 없음" 모순 상태 정리 (앱 재시작 시점 stale UserDefaults 대응)
        DevToolsSettings.shared.validateSelection()

        // DevToolsSettings 구독: locationType 또는 selectedRecordingFileName 변경 시 즉시 반영
        Publishers.CombineLatest(
            DevToolsSettings.shared.locationType,
            DevToolsSettings.shared.selectedRecordingFileName
        )
        .removeDuplicates(by: { lhs, rhs in lhs.0 == rhs.0 && lhs.1 == rhs.1 })
        .sink { [weak self] type, _ in
            self?.applyLocationType(type)
        }
        .store(in: &cancellables)
    }

    /// DevToolsSettings 변화 시 LocationService.activeProvider 갱신
    /// - Real: RealGPSProvider 활성화
    /// - File (유효 파일): FileGPSProvider 활성화 — 즉시 좌표 흐름 시작
    private func applyLocationType(_ type: DevToolsSettings.LocationType) {
        switch type {
        case .real:
            coordLogger.debug("[NAV] applyLocationType=Real")
            LocationService.shared.setProvider(RealGPSProvider(locationService: locationService))
        case .file:
            guard let url = DevToolsSettings.shared.selectedRecordingFileURL else {
                // 모순 상태 — Real로 fallback
                coordLogger.debug("[NAV] applyLocationType=File but no file → Real로 fallback")
                DevToolsSettings.shared.validateSelection()
                LocationService.shared.setProvider(RealGPSProvider(locationService: locationService))
                return
            }
            coordLogger.debug("[NAV] applyLocationType=File \(url.lastPathComponent, privacy: .public)")
            LocationService.shared.setProvider(FileGPSProvider(fileURL: url))
        }
    }

    // MARK: - Start

    func start() {
        let mapVC = MapViewController(locationService: locationService)
        self.mapViewController = mapVC

        let homeViewModel = HomeViewModel(locationService: locationService)
        self.homeViewModel = homeViewModel
        let homeVC = HomeViewController(
            viewModel: homeViewModel,
            mapViewController: mapVC
        )
        self.homeViewController = homeVC

        mapVC.onPOISelected = { [weak self] place in
            self?.showPOIDetail(place)
        }

        mapVC.onBikeStationSelected = { [weak self] station in
            self?.showBikeStationDetail(station)
        }

        mapVC.onBusStopSelected = { [weak self] busStop in
            self?.showBusStopDetail(busStop)
        }

        mapVC.onEmptyMapTapped = { [weak self] in
            guard self?.mapItemDetailDrawer != nil else { return }
            self?.dismissMapItemDetailWithCleanup()
        }

        mapVC.onLongPressDropped = { [weak self] coordinate in
            self?.showNeighborhoodInsight(at: coordinate)
        }

        navigationController.delegate = self
        navigationController.setViewControllers([homeVC], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        bindSessionManager()
        setupDebugOverlayObserver()
        setupDrawerHeightCallback()

        DispatchQueue.main.async { [weak self] in
            self?.presentHomeDrawer()
            self?.mapViewController.moveToInitialLocation()
        }
    }

    // MARK: - Home Drawer Management

    private func presentHomeDrawer() {
        guard homeDrawerVC == nil,
              navigationController.topViewController === homeViewController else { return }

        let drawerVC = HomeDrawerViewController(viewModel: homeViewModel)
        homeDrawerVC = drawerVC

        drawerVC.onFavoriteTapped = { [weak self] favorite in
            self?.showRoutePreviewForFavorite(favorite)
        }
        drawerVC.onCategoryTapped = { [weak self] category in
            self?.searchCategory(category)
        }

        drawerVC.onRecentSearchTapped = { [weak self] history in
            self?.showRoutePreviewForHistory(history)
        }

        drawerVC.onSearchBarTapped = { [weak self] in
            self?.handleSearchBarTapped()
        }

        drawerVC.onSettingsTapped = { [weak self] in
            self?.showSettings()
        }

        drawerManager.pushDrawer(
            drawerVC,
            detents: standardDetents(),
            initialDetent: homeInitialDetent(),
            animated: false
        )
    }

    private func restoreHomeDrawer() {
        guard let drawerVC = homeDrawerVC else {
            presentHomeDrawer()
            return
        }

        // If home is already the only item in stack, no-op
        if drawerManager.topViewController === drawerVC {
            return
        }

        drawerManager.replaceStack(
            with: drawerVC,
            detents: standardDetents(),
            initialDetent: homeInitialDetent()
        )
    }

    // MARK: - POI Detail Flow

    private func showPOIDetail(_ place: Place) {
        guard navigationController.topViewController === homeViewController else { return }
        mapViewController.showPOIMarker(for: place)
        let content = makePlaceContent(place)
        showMapItemDetail(content: content)
    }

    private func showPOIDetailFromDrawer(_ place: Place) {
        guard currentDrawer != nil else { return }
        mapViewController.showPOIMarker(for: place)
        let content = makePlaceContent(place)
        showMapItemDetail(content: content)
    }

    private func makePlaceContent(_ place: Place) -> PlaceContent {
        let content = PlaceContent(place: place)
        content.onRouteTapped = { [weak self] place in
            self?.dismissIntermediateDrawers {
                self?.showRoutePreview(to: place)
            }
        }
        return content
    }

    private func dismissSearchResultDrawerWithCleanup() {
        mapItemDetailDrawer = nil
        currentDrawer = nil
        lastSearchQuery = ""
        mapViewController.clearSearchResults()
        mapViewController.onAnnotationSelected = nil
        mapViewController.onRegionChanged = nil
        restoreHomeDrawer()
    }

    // MARK: - Bike Station Detail Flow

    func showBikeStationDetail(_ station: BikeStation) {
        guard navigationController.topViewController === homeViewController else { return }
        // POI 와 동일 — 지도를 정류소 중심으로 이동 + 마커 선택 상태 유지
        mapViewController.focusBikeStation(station, zoomIn: false)

        let content = BikeStationContent(station: station)
        content.onWalkingRoute = { [weak self] station in
            self?.showWalkingRouteToBikeStation(station)
        }
        content.onRent = {
            BikeAppLauncher.openRent()
        }
        showMapItemDetail(content: content)
    }

    /// 따릉이 정류소까지 도보 길찾기 — 상세 시트 닫고 RoutePreview 표시
    private func showWalkingRouteToBikeStation(_ station: BikeStation) {
        guard navigationController.topViewController === homeViewController else { return }
        dismissMapItemDetailWithCleanup()

        mapViewController.clearSearchResults()
        mapViewController.showDestination(
            coordinate: station.coordinate,
            title: station.stationName,
            subtitle: nil
        )

        let userCoordinate = locationService.bestAvailableLocation?.coordinate
            ?? mapViewController.mapView.centerCoordinate

        presentRoutePreviewDrawer(
            origin: userCoordinate,
            destination: station.coordinate,
            destinationName: station.stationName,
            destinationAddress: nil,
            transportMode: .walking
        )
    }

    // MARK: - Bus Stop Detail Flow

    func showBusStopDetail(_ busStop: BusStop) {
        guard navigationController.topViewController === homeViewController else { return }
        mapViewController.mapView.setCenter(busStop.coordinate, animated: true)

        let content = BusStopContent(busStop: busStop)
        content.onWalkingRoute = { [weak self] stop in
            self?.showWalkingRouteToBusStop(stop)
        }
        content.onRouteTapped = { [weak self] arrival in
            self?.showBusRoute(arrival: arrival, fromStop: busStop)
        }
        content.onTimetableTapped = { [weak self] in
            guard let self else { return }
            // 현재 도착 정보가 로드됐을 때만 시간표 진입
            // BusStopContent가 arrivals를 보유하지 않으므로 별도 fetch 없이 빈 목록으로 시작
            self.showBusStopTimetable(busStop: busStop, arrivals: [])
        }
        showMapItemDetail(content: content)
    }

    private func showWalkingRouteToBusStop(_ busStop: BusStop) {
        guard navigationController.topViewController === homeViewController else { return }
        dismissMapItemDetailWithCleanup()

        mapViewController.showDestination(
            coordinate: busStop.coordinate,
            title: busStop.name,
            subtitle: nil
        )

        let userCoordinate = locationService.bestAvailableLocation?.coordinate
            ?? mapViewController.mapView.centerCoordinate

        presentRoutePreviewDrawer(
            origin: userCoordinate,
            destination: busStop.coordinate,
            destinationName: busStop.name,
            destinationAddress: nil,
            transportMode: .walking
        )
    }

    // MARK: - Bus Route Detail Flow

    func showBusRoute(arrival: BusArrival, fromStop: BusStop?) {
        // 기존 노선 드로어가 열려있으면 제거
        if let existing = transitRouteDrawer {
            drawerManager.popDrawer()
            transitRouteDrawer = nil
            if existing === existing { /* 동일 노선 재탭 시 닫기만 */ }
        }

        let drawer = BusRouteDrawerViewController(
            arrival: arrival,
            currentStopArsId: fromStop?.arsId,
            api: .shared
        )

        drawer.onClose = { [weak self] in
            self?.dismissTransitRouteDrawer()
        }

        // 정류소 탭 → 지도 카메라 이동 (드로어 유지)
        drawer.onStopTapped = { [weak self] stop in
            let coord = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)
            self?.mapViewController.mapView.setCenter(coord, animated: true)
        }

        transitRouteDrawer = drawer
        drawerManager.pushDrawer(drawer, detents: standardDetents(), initialDetent: homeInitialDetent())

        // 노선 포커스: 선택 정류장 외 버스/따릉이 마커 숨김
        mapViewController.enterRouteFocus(keepingStopArsId: fromStop?.arsId)
        mapViewController.clearBusVehicles()
        mapViewController.clearRouteStops()

        // 노선 폴리라인 + 경유 정류소 마커 표시
        Task {
            if let stops = try? await BusAPIClient.shared.fetchRouteStops(routeId: arrival.routeId) {
                let (primary, opposite) = Self.directionSegments(stops, selectedArsId: fromStop?.arsId)
                let primaryCoords = primary.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let oppositeCoords = opposite.map { run in
                    run.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                }
                await MainActor.run {
                    self.mapViewController.showBusRoutePolyline(primary: primaryCoords, opposite: oppositeCoords)
                    self.mapViewController.showRouteStops(stops, excludingArsId: fromStop?.arsId)
                }
            }
        }

        // 실시간 운행 차량 위치 1회 조회 후 표시 (서비스 미구독 시 빈 결과 → 무시)
        Task {
            if let vehicles = try? await BusAPIClient.shared.fetchBusPositions(routeId: arrival.routeId) {
                await MainActor.run {
                    self.mapViewController.showBusVehicles(vehicles)
                }
            }
        }
    }

    /// 노선 정류소를 진행 방향(direction) 기준 상/하행 구간으로 분리한다.
    /// - direction 값이 바뀌는 회차 지점에서 구간이 나뉜다.
    /// - selectedArsId가 포함된 구간을 primary(짙은 색), 나머지를 opposite로 반환.
    /// - 방향 데이터가 없거나 한 방향뿐이면 전체를 primary로 반환(단색 폴백).
    static func directionSegments(
        _ stops: [BusRouteStop],
        selectedArsId: String?
    ) -> (primary: [BusRouteStop], opposite: [[BusRouteStop]]) {
        guard let first = stops.first else { return ([], []) }

        // direction 기준 연속 구간(run)으로 분할. 빈 direction은 직전 구간에 흡수.
        var runs: [[BusRouteStop]] = []
        var current: [BusRouteStop] = [first]
        for stop in stops.dropFirst() {
            let last = current[current.count - 1]
            if stop.direction.isEmpty || stop.direction == last.direction {
                current.append(stop)
            } else {
                runs.append(current)
                current = [stop]
            }
        }
        runs.append(current)

        guard runs.count > 1 else { return (stops, []) }

        let primaryIndex: Int = {
            guard let sel = selectedArsId else { return 0 }
            return runs.firstIndex { run in run.contains { $0.arsId == sel } } ?? 0
        }()

        let primary = runs[primaryIndex]
        let opposite = runs.enumerated()
            .filter { $0.offset != primaryIndex }
            .map { $0.element }
        return (primary, opposite)
    }

    func showBusStopTimetable(busStop: BusStop, arrivals: [BusArrival]) {
        let drawer = BusStopTimetableDrawerViewController(busStop: busStop, arrivals: arrivals)
        drawer.onClose = { [weak self] in
            self?.transitRouteDrawer = nil
            self?.drawerManager.popDrawer()
        }
        transitRouteDrawer = drawer
        drawerManager.pushDrawer(drawer, detents: standardDetents(), initialDetent: homeInitialDetent())
    }

    private func dismissTransitRouteDrawer() {
        transitRouteDrawer = nil
        drawerManager.popDrawer()
        mapViewController.clearTransitPolyline()
        mapViewController.exitRouteFocus()
    }

    // MARK: - Unified Map Item Detail Flow

    /// POI, 따릉이 등 통합 상세 시트 표시
    /// - 드로어가 닫혀있으면 새로 push
    /// - 열려있으면 컨텐츠 교체 (헤더 + 본문 + 푸터 모두 갱신)
    // MARK: - Neighborhood Insight (핀 기반 동네 인사이트)

    func showNeighborhoodInsight(at coordinate: CLLocationCoordinate2D) {
        print("[Insight] 2. resolving region…")
        Task { @MainActor in
            do {
                let region = try await regionCodeService.regionCode(at: coordinate)
                print("[Insight] 3. region = \(region.guName) \(region.dongName) (code \(region.dongCode))")
                let content = PinInsightContent(coordinate: coordinate, region: region)
                let regionName = region.displayAddress
                content.onRouteTapped = { [weak self] coord in
                    self?.showRouteToInsight(coordinate: coord, name: regionName)
                }
                content.onSave = { [weak self] coord, name in
                    DataService.shared.saveFavoriteFromCoordinate(
                        name: name, address: name,
                        latitude: coord.latitude, longitude: coord.longitude,
                        category: "neighborhood"
                    )
                    print("[Insight] saved favorite: \(name)")
                    self?.presentInsightToast("‘\(name)’ 관심 동네에 저장됨")
                }
                content.onShare = { [weak self] text in
                    self?.presentInsightShare(text)
                }
                self.showMapItemDetail(content: content)
                print("[Insight] 4. popup presented")
            } catch RegionCodeError.outsideSeoul {
                print("[Insight] X. outside Seoul — 서울만 지원")
                self.mapViewController?.clearInsightPin()
            } catch {
                print("[Insight] X. region resolve failed: \(error)")
                self.mapViewController?.clearInsightPin()
            }
        }
    }

    /// 인사이트 공유 시트 (US3)
    private func presentInsightShare(_ text: String) {
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        let presenter = navigationController.topViewController ?? navigationController
        vc.popoverPresentationController?.sourceView = presenter.view
        presenter.present(vc, animated: true)
    }

    /// 저장 확인 토스트 (US3)
    private func presentInsightToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let presenter = navigationController.topViewController ?? navigationController
        presenter.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak alert] in
            alert?.dismiss(animated: true)
        }
    }

    /// 인사이트 핀 좌표까지 경로 미리보기 (US2)
    private func showRouteToInsight(coordinate: CLLocationCoordinate2D, name: String) {
        dismissIntermediateDrawers { [weak self] in
            guard let self else { return }
            let userCoordinate = self.locationService.bestAvailableLocation?.coordinate
                ?? self.mapViewController.mapView.centerCoordinate
            self.mapViewController.showDestination(coordinate: coordinate, title: name, subtitle: nil)
            self.presentRoutePreviewDrawer(origin: userCoordinate, destination: coordinate, destinationName: name)
        }
    }

    private func showMapItemDetail(content: any MapItemContent) {
        // 노선/시간표 드로어가 위에 떠 있으면 먼저 닫아 상세가 최상단에 오도록
        if transitRouteDrawer != nil {
            dismissTransitRouteDrawer()
        }

        let currentCoord = locationService.locationPublisher.value?.coordinate

        if let existing = mapItemDetailDrawer {
            existing.update(content: content)
            existing.updateDistance(from: currentCoord)
            return
        }

        let detailVC = MapItemDetailViewController(content: content)
        mapItemDetailDrawer = detailVC
        detailVC.updateDistance(from: currentCoord)
        detailVC.onClose = { [weak self] in
            self?.dismissMapItemDetailWithCleanup()
        }

        drawerManager.pushDrawer(
            detailVC,
            detents: standardDetents(),
            initialDetent: homeInitialDetent()
        )
    }

    private func dismissMapItemDetailWithCleanup() {
        mapItemDetailDrawer = nil
        // POI 마커가 떠있다면 함께 정리 (멱등)
        mapViewController.clearPOIMarker()
        // 따릉이/버스 마커의 선택 상태 해제
        mapViewController.deselectAllBikeStations()
        mapViewController.deselectAllBusStops()
        // 인사이트 핀 제거 (멱등)
        mapViewController.clearInsightPin()
        drawerManager.popDrawer()
    }

    private func dismissAllDrawers(completion: (() -> Void)? = nil) {
        currentDrawer = nil
        mapItemDetailDrawer = nil
        routePreviewDrawer = nil
        mapViewController.clearSearchResults()
        mapViewController.clearRoutes()
        mapViewController.clearDestination()
        mapViewController.onAnnotationSelected = nil
        drawerManager.replaceStack(
            with: homeDrawerVC ?? HomeDrawerViewController(viewModel: homeViewModel),
            detents: standardDetents(),
            initialDetent: homeInitialDetent(),
            animated: false
        )
        completion?()
    }

    /// Top map inset: safeArea top with margin
    private func mapTopInset(in containerView: UIView) -> CGFloat {
        return containerView.safeAreaInsets.top + Theme.Spacing.sm
    }

    /// Maximum drawer height: from safeArea bottom to safeArea top
    /// DrawerContainerManager adds safeAreaInsets.bottom to the height for the home indicator area,
    /// so subtract it here to keep the drawer's visible top edge at safeArea top.
    private func drawerMaxHeight(in containerView: UIView) -> CGFloat {
        return containerView.bounds.height - containerView.safeAreaInsets.top - containerView.safeAreaInsets.bottom
    }

    private func drawerMediumHeight(in containerView: UIView) -> CGFloat {
        return drawerMaxHeight(in: containerView) * 0.5
    }

    private func standardDetents() -> [DrawerDetent] {
        let containerView = navigationController.view!
        return [
            .absolute(200, id: "small"),
            .absolute(drawerMediumHeight(in: containerView), id: "drawerMedium"),
            .absolute(drawerMaxHeight(in: containerView), id: "drawerLarge"),
        ]
    }

    private func homeInitialDetent() -> DrawerDetent {
        let containerView = navigationController.view!
        return .absolute(drawerMediumHeight(in: containerView), id: "drawerMedium")
    }

    // MARK: - Debug Overlay

    private func setupDebugOverlayObserver() {
        // Apply initial state
        if UserDefaults.standard.bool(forKey: "devtools_debug_overlay_enabled") {
            mapViewController.showDebugOverlay()
        }

        // Observe changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let enabled = UserDefaults.standard.bool(forKey: "devtools_debug_overlay_enabled")
            if enabled {
                self?.mapViewController.showDebugOverlay()
                self?.navigationMapViewController?.showDebugOverlay()
            } else {
                self?.mapViewController.hideDebugOverlay()
                self?.navigationMapViewController?.hideDebugOverlay()
            }
        }
    }

    private func setupDrawerHeightCallback() {
        drawerManager.onHeightChanged = { [weak self] height in
            guard let self else { return }
            let containerView = self.navigationController.view!
            let effectiveHeight = min(height, self.drawerMediumHeight(in: containerView))
            self.homeViewController.updateMapControlBottomOffset(effectiveHeight)
            self.homeViewController.updateMapInsets(
                top: self.mapTopInset(in: containerView),
                bottom: effectiveHeight
            )
        }
    }

    // MARK: - Session Manager Binding (CarPlay ↔ iPhone sync)

    private func bindSessionManager() {
        sessionManager.navigationCommandPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] command in
                switch command {
                case .started(let source):
                    if source == .carPlay {
                        // Navigation started from CarPlay → show on iPhone
                        self?.handleCarPlayNavigationStarted()
                    }
                case .stopped:
                    // Navigation stopped (from either side)
                    self?.cleanUpNavigationUI()
                }
            }
            .store(in: &cancellables)
    }

    private func handleCarPlayNavigationStarted() {
        guard sessionManager.activeSession != nil else { return }

        // TODO: 주행 중 여부 체크는 Step 8에서 NavigationVC 연결 시 교체
        // 현재는 CarPlay에서 시작해도 iPhone에 주행 화면을 표시하지 않음 (stub)
        print("[TODO] handleCarPlayNavigationStarted - Step 8에서 구현 예정")
    }

    private func presentNavigationFromSession(_ session: NavigationSession) {
        // TODO: 새 NavigationEngine + NavigationViewController로 교체 예정
        print("[TODO] presentNavigationFromSession - 새 엔진으로 교체 예정")
    }

    // MARK: - Settings Flow

    private func showSettings() {
        let settingsVM = SettingsViewModel()
        let settingsVC = SettingsViewController(viewModel: settingsVM)

        settingsVC.onDismiss = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }

        settingsVC.onShowDevTools = { [weak self] in
            self?.showDevTools()
        }

        navigationController.pushViewController(settingsVC, animated: true)
    }

    // MARK: - DevTools Flow

    private func showDevTools() {
        let devToolsVM = DevToolsViewModel()
        let devToolsVC = DevToolsViewController(viewModel: devToolsVM)

        devToolsVC.onDismiss = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }

        devToolsVC.onShowFileList = { [weak self] in
            self?.showRecordingFileList()
        }

        devToolsVC.onSelectRecordingFile = { [weak self] in
            self?.showRecordingFileList()
        }

        navigationController.pushViewController(devToolsVC, animated: true)
    }

    private func showRecordingFileList() {
        let fileListVC = RecordingFileListViewController()

        fileListVC.onDismiss = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }

        // 파일 탭 시 File 모드로 자동 전환 + 선택 저장 + 뒤로
        fileListVC.onSelectFile = { [weak self] record in
            DevToolsSettings.shared.setLocationType(.file)
            DevToolsSettings.shared.setSelectedRecordingFileName(record.fileName)
            self?.navigationController.popViewController(animated: true)
        }

        navigationController.pushViewController(fileListVC, animated: true)
    }

    // MARK: - Favorite / History Quick Navigate

    private func showRoutePreviewForFavorite(_ favorite: FavoritePlace) {
        dismissIntermediateDrawers { [weak self] in
            guard let self else { return }
            let destination = CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude)
            let userCoordinate = self.locationService.bestAvailableLocation?.coordinate
                ?? self.mapViewController.mapView.centerCoordinate

            self.mapViewController.showDestination(coordinate: destination, title: favorite.name, subtitle: favorite.address)
            self.presentRoutePreviewDrawer(origin: userCoordinate, destination: destination, destinationName: favorite.name, destinationAddress: favorite.address)
        }
    }

    private func showRoutePreviewForHistory(_ history: SearchHistory) {
        dismissIntermediateDrawers { [weak self] in
            guard let self else { return }
            let destination = history.coordinate
            let userCoordinate = self.locationService.bestAvailableLocation?.coordinate
                ?? self.mapViewController.mapView.centerCoordinate

            self.mapViewController.showDestination(coordinate: destination, title: history.placeName, subtitle: history.address)
            self.presentRoutePreviewDrawer(origin: userCoordinate, destination: destination, destinationName: history.placeName, destinationAddress: history.address)
        }
    }

    private func dismissIntermediateDrawers(completion: (() -> Void)? = nil) {
        if routePreviewDrawer != nil {
            routePreviewDrawer = nil
            mapViewController.clearRoutes()
            mapViewController.clearDestination()
        }
        if currentDrawer != nil {
            currentDrawer = nil
            mapViewController.clearSearchResults()
            mapViewController.onAnnotationSelected = nil
        }
        mapItemDetailDrawer = nil
        completion?()
    }

    // MARK: - Search Flow

    private func searchCategory(_ category: SearchCategory) {
        let region = mapViewController.mapView.region
        let provider = LBSServiceProvider.shared.searchProviderType.rawValue

        Task {
            do {
                let results = try await searchService.searchCategory(
                    category,
                    region: region,
                    regionMode: .biased
                )
                showSearchResults(results, query: category.name)
            } catch {
            }
        }
    }

    private func handleSearchBarTapped() {
        showSearch()
    }

    private func showSearch() {
        // Clean up any existing drawer state
        if currentDrawer != nil {
            currentDrawer = nil
            mapViewController.clearSearchResults()
            mapViewController.onAnnotationSelected = nil
        }
        mapItemDetailDrawer = nil

        let mapRegion = mapViewController.mapView.region

        let searchViewModel = SearchViewModel(
            searchService: searchService
        )
        searchViewModel.updateSearchRegion(mapRegion)
        let searchVC = SearchViewController(viewModel: searchViewModel)
        searchVC.modalPresentationStyle = .overFullScreen

        searchVC.onDismiss = { [weak self, weak searchVC] in
            guard let searchVC else { return }
            self?.drawerManager.snapToDetent(id: "drawerMedium")
            UIView.animate(withDuration: 0.25, animations: {
                searchVC.view.alpha = 0
            }) { _ in
                self?.navigationController.dismiss(animated: false)
            }
        }

        searchVC.onSearchResults = { [weak self, weak searchVC] results, query in
            guard let searchVC else { return }
            print("[AppCoordinator] onSearchResults: \(results.count) results for '\(query)'")
            self?.drawerManager.snapToDetent(id: "drawerMedium")
            UIView.animate(withDuration: 0.25, animations: {
                searchVC.view.alpha = 0
            }) { _ in
                print("[AppCoordinator] dismiss completion → calling showSearchResults")
                self?.navigationController.dismiss(animated: false)
                // Delay to next run loop so map view layout is stable after dismiss
                DispatchQueue.main.async {
                    print("[AppCoordinator] DispatchQueue.main.async → showSearchResults now")
                    self?.showSearchResults(results, query: query)
                }
            }
        }

        // Present transparent, then fade in with drawer snap
        searchVC.loadViewIfNeeded()
        searchVC.view.alpha = 0
        navigationController.present(searchVC, animated: false)

        drawerManager.snapToDetent(id: "drawerLarge")
        UIView.animate(withDuration: 0.3) {
            searchVC.view.alpha = 1
        }
    }

    private func showSearchResults(_ results: [Place], query: String = "") {
        // Add markers on map (without fit — fit happens after drawer push)
        mapViewController.addSearchResults(results)
        lastSearchQuery = query

        // Create search result drawer
        let drawerVC = SearchResultDrawerViewController(query: query)
        drawerVC.updateResults(results)
        currentDrawer = drawerVC

        // Drawer close button
        drawerVC.onClose = { [weak self] in
            self?.dismissSearchResultDrawerWithCleanup()
        }

        // Drawer -> Map sync: item tapped
        drawerVC.onItemSelected = { [weak self] place, index in
            self?.currentDrawer?.scrollToIndex(index, animated: false)
            self?.mapViewController.focusAnnotation(at: index)
            self?.showPOIDetailFromDrawer(place)
        }

        // Drawer -> Map sync: scroll changes focused annotation
        drawerVC.onFocusedIndexChanged = { [weak self] index in
            self?.mapViewController.focusAnnotation(at: index)
        }

        // Map -> Drawer sync: annotation tapped
        mapViewController.onAnnotationSelected = { [weak self] index in
            self?.currentDrawer?.scrollToIndex(index)
            if let place = self?.currentDrawer?.place(at: index),
               let existing = self?.mapItemDetailDrawer {
                let content = self?.makePlaceContent(place)
                if let content = content {
                    existing.update(content: content)
                }
            }
        }

        // Region change → show refresh button
        mapViewController.onRegionChanged = { [weak self] in
            self?.currentDrawer?.showRefreshButton()
        }

        // Load more results (pagination)
        drawerVC.onLoadMore = { [weak self] in
            guard let self else { return nil }
            do {
                let more = try await self.searchService.loadMoreResults()
                guard !more.isEmpty else { return nil }
                self.mapViewController.appendSearchResults(more)
                return more
            } catch {
                return nil
            }
        }

        // Research button tapped
        drawerVC.onResearch = { [weak self] in
            self?.executeResearch()
        }

        // Present drawer first, then fit map to results after layout settles
        drawerManager.pushDrawer(
            drawerVC,
            detents: standardDetents(),
            initialDetent: homeInitialDetent()
        )

        // Fit map after drawer push so layoutMargins are stable
        DispatchQueue.main.async { [weak self] in
            self?.mapViewController.fitToSearchResults()
        }
    }

    private func executeResearch() {
        let query = lastSearchQuery
        guard !query.isEmpty else { return }
        let region = mapViewController.mapView.region
        let provider = LBSServiceProvider.shared.searchProviderType.rawValue

        Task {
            do {
                let results = try await searchService.search(
                    query: query,
                    region: region,
                    regionMode: .strict
                )
                mapViewController.clearSearchResults()
                mapViewController.showSearchResults(results)
                currentDrawer?.updateResults(results)
            } catch {
            }
        }
    }

    // MARK: - Route Preview Flow

    private func showRoutePreview(to place: Place) {
        // Clear search markers
        mapViewController.clearSearchResults()

        // Show destination pin
        let coordinate = place.coordinate
        mapViewController.showDestination(
            coordinate: coordinate,
            title: place.name,
            subtitle: place.address
        )

        // Get current user location
        let userCoordinate = locationService.bestAvailableLocation?.coordinate
            ?? mapViewController.mapView.centerCoordinate

        // Present route preview as drawer (map stays in HomeVC)
        presentRoutePreviewDrawer(
            origin: userCoordinate,
            destination: coordinate,
            destinationName: place.name,
            destinationAddress: place.address
        )
    }

    // MARK: - Route Preview Drawer

    private func presentRoutePreviewDrawer(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationName: String?,
        destinationAddress: String? = nil,
        transportMode: TransportMode = .automobile
    ) {
        // Save as recent destination
        let place = Place(
            name: destinationName,
            coordinate: destination,
            address: destinationAddress,
            phoneNumber: nil, url: nil, category: nil, providerRawData: nil
        )
        DataService.shared.saveSearchHistory(query: destinationName ?? "", place: place)
        homeViewModel.loadHomeData()
        let routePreviewVM = RoutePreviewViewModel(
            routeService: routeService,
            origin: origin,
            destination: destination,
            destinationName: destinationName,
            transportMode: transportMode
        )

        let drawerVC = RoutePreviewDrawerViewController(viewModel: routePreviewVM)
        routePreviewDrawer = drawerVC

        drawerVC.onClose = { [weak self] in
            self?.dismissRoutePreviewDrawerWithCleanup()
        }

        drawerVC.onRoutesChanged = { [weak self] routes, selectedIndex in
            self?.mapViewController.showRoutes(routes, selectedIndex: selectedIndex)
        }

        drawerVC.onStartNavigation = { [weak self] route, transportMode in
            let place = Place(
                name: destinationName,
                coordinate: destination,
                address: nil,
                phoneNumber: nil, url: nil, category: nil, providerRawData: nil
            )
            self?.startNavigation(with: route, destination: place, transportMode: transportMode)
        }

        drawerVC.onStartVirtualDrive = { [weak self] route, transportMode in
            self?.startVirtualDrive(with: route, destinationName: destinationName, transportMode: transportMode)
        }

        // Clear intermediate state and replace stack
        currentDrawer = nil
        mapItemDetailDrawer = nil
        mapViewController.onAnnotationSelected = nil

        drawerManager.replaceStack(
            with: drawerVC,
            detents: standardDetents(),
            initialDetent: homeInitialDetent()
        )
    }

    private func dismissRoutePreviewDrawerWithCleanup() {
        routePreviewDrawer = nil
        mapViewController.clearRoutes()
        mapViewController.clearDestination()
        restoreHomeDrawer()
    }

    // MARK: - Navigation Map Factory

    private func createNavigationMapVC() -> MapViewController {
        let mapVC = MapViewController(locationService: locationService)
        return mapVC
    }

    // MARK: - Navigation Flow

    private func startNavigation(
        with route: Route,
        destination: Place? = nil,
        transportMode: TransportMode = .automobile,
        forceSimul: Bool = false
    ) {
        let lastCoord = route.polylineCoordinates.last ?? CLLocationCoordinate2D()
        let resolvedDestination = destination
            ?? Place(name: nil, coordinate: lastCoord, address: nil, phoneNumber: nil, url: nil, category: nil, providerRawData: nil)

        // locationPublisher / recordingMode 결정
        let locationPublisher: AnyPublisher<CLLocation, Never>
        let recordingMode: LocationRecorder.RecordingMode

        if forceSimul {
            // 가상 주행: 별도 driver 생성, lifecycle은 안내 종료까지
            // start()는 sessionManager 구독 이후에 호출해야 첫 GPS tick을 엔진이 받음
            coordLogger.debug("[NAV] GPS=Simul")
            let driver = VirtualDriveDriver()
            driver.loadSteps(route.steps)
            activeVirtualDriveDriver = driver

            locationPublisher = driver.locationPublisher
            recordingMode = .simul
        } else {
            // 일반 안내: LocationService.activeProvider (Real or File)가 이미 흐름
            let type = DevToolsSettings.shared.locationType.value
            coordLogger.debug("[NAV] GPS=\(type.rawValue, privacy: .public)")
            locationPublisher = LocationService.shared.locationPublisher.compactMap { $0 }.eraseToAnyPublisher()
            recordingMode = (type == .real) ? .real : .simul
        }

        // GPX 녹화 자동 시작 (armed 상태면)
        startRecordingIfArmed(
            mode: recordingMode,
            originName: nil,
            destinationName: resolvedDestination.name,
            locationSource: locationPublisher
        )

        // 엔진 시작
        sessionManager.startNavigation(
            route: route,
            destination: resolvedDestination,
            transportMode: transportMode,
            locationPublisher: locationPublisher,
            source: .phone
        )

        // 가상 주행: sessionManager 구독 완료 후 start → 첫 GPS tick 유실 없음
        if forceSimul {
            activeVirtualDriveDriver?.start(
                polyline: route.polylineCoordinates,
                transportMode: transportMode
            )
        }

        // 주행 화면 생성 + 엔진 바인딩
        dismissAllDrawers { [weak self] in
            guard let self else { return }

            let navVC = NavigationViewController(
                route: route,
                transportMode: transportMode,
                destinationName: resolvedDestination.name,
                virtualDriveDriver: self.activeVirtualDriveDriver
            )
            navVC.bind(
                guide: self.sessionManager.guidePublisher,
                route: self.sessionManager.routePublisher
            )
            navVC.onDismiss = { [weak self] in
                self?.dismissNavigation()
            }
            navVC.onReroute = { [weak self] in
                self?.sessionManager.requestReroute()
            }

            self.navigationController.pushViewController(navVC, animated: true)
        }
    }

    private func dismissNavigation() {
        VoiceTTSPlayer.shared.stop()

        // GPX 녹화 자동 종료 (recording 상태면)
        finishRecordingIfRecording()

        sessionManager.stopNavigation()

        // 가상 주행 driver 정리 (있으면)
        activeVirtualDriveDriver?.stop()
        activeVirtualDriveDriver = nil

        navigationMapViewController = nil
        // 시스템 setUserTrackingMode은 showsUserLocation을 암묵적으로 켜 시스템 파란점이 부활하므로 사용 X
        mapViewController.setUserTrackingMode(.follow)
        navigationController.popToViewController(homeViewController, animated: true)
    }

    // MARK: - GPX Recording (1회 자동 녹화)

    /// armed 상태면 자동으로 녹화 시작
    /// - locationSource: 좌표 소스 (Real/File: LocationService, 가상주행: driver.locationPublisher)
    private func startRecordingIfArmed(
        mode: LocationRecorder.RecordingMode,
        originName: String?,
        destinationName: String?,
        locationSource: AnyPublisher<CLLocation, Never>
    ) {
        let recorder = LocationRecorder.shared
        print("[Recording] startRecordingIfArmed() — isArmed=\(recorder.isArmed) mode=\(mode.rawValue)")
        guard recorder.isArmed else { return }

        recorder.startRecording(
            mode: mode,
            originName: originName,
            destinationName: destinationName,
            locationSource: locationSource
        )
    }

    /// 녹화 중이면 종료 + 파일 저장 + DataService 기록
    private func finishRecordingIfRecording() {
        let recorder = LocationRecorder.shared
        print("[Recording] finishRecordingIfRecording() — state=\(recorder.statePublisher.value)")
        guard recorder.statePublisher.value == .recording else { return }

        let result = recorder.stopRecording()

        // DataService 저장
        if let result {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: result.fileURL.path)[.size] as? Int64) ?? 0
            let relativePath = "Recordings/\(result.fileURL.lastPathComponent)"
            DataService.shared.saveRecording(
                fileName: result.fileURL.lastPathComponent,
                filePath: relativePath,
                duration: result.duration,
                distance: result.distance,
                pointCount: result.pointCount,
                fileSize: fileSize,
                recordingMode: result.recordingMode.rawValue,
                originName: result.originName,
                destinationName: result.destinationName
            )
            print("[Recording] DataService.saveRecording OK — \(result.fileURL.lastPathComponent) points=\(result.pointCount) dist=\(Int(result.distance))m")
        } else {
            print("[Recording] DataService.saveRecording skipped — result=nil")
        }
    }

    // MARK: - Virtual Drive Flow

    private func startVirtualDrive(with route: Route, destinationName: String? = nil, transportMode: TransportMode = .automobile) {
        let destination = destinationName.map {
            Place(name: $0, coordinate: route.polylineCoordinates.last ?? CLLocationCoordinate2D(), address: nil, phoneNumber: nil, url: nil, category: nil, providerRawData: nil)
        }
        startNavigation(with: route, destination: destination, transportMode: transportMode, forceSimul: true)
    }

    private func cleanUpNavigationUI() {
        navigationMapViewController = nil
        // 시스템 setUserTrackingMode은 showsUserLocation을 암묵적으로 켜 시스템 파란점이 부활하므로 사용 X
        mapViewController.setUserTrackingMode(.follow)
        navigationController.popToViewController(homeViewController, animated: true)
    }
}

// MARK: - UINavigationControllerDelegate

extension AppCoordinator: UINavigationControllerDelegate {

    nonisolated func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        MainActor.assumeIsolated {
            if viewController === homeViewController, homeDrawerVC == nil {
                presentHomeDrawer()
            }
        }
    }
}
