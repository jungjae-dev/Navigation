import UIKit
import MapKit
import Combine
import CoreLocation

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
    private var poiDetailDrawer: POIDetailViewController?
    private var routePreviewDrawer: RoutePreviewDrawerViewController?
    private var cancellables = Set<AnyCancellable>()

    private var drawerManager: DrawerContainerManager {
        homeViewController.drawerManager
    }

    // MARK: - iPhone-only Navigation Services (stub — 새 엔진 구현 시 교체 예정)

    // MARK: - Navigation Map (ephemeral, created per session)

    private var navigationMapViewController: MapViewController?

    // MARK: - Virtual Drive / GPX

    /// 가상 주행 진행 중인 driver (안내 lifecycle에 종속)
    private var activeVirtualDriveDriver: VirtualDriveDriver?
    private var simulationCancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(window: UIWindow) {
        self.window = window
        self.locationService = .shared
        self.navigationController = UINavigationController()
        self.navigationController.isNavigationBarHidden = true

        super.init()

        // "File 모드인데 파일 없음" 모순 상태 정리 (앱 재시작 시점 stale UserDefaults 대응)
        DevToolsSettings.shared.validateSelection()

        // DevToolsSettings 구독: locationType 또는 selectedGPXFileName 변경 시 즉시 반영
        Publishers.CombineLatest(
            DevToolsSettings.shared.locationType,
            DevToolsSettings.shared.selectedGPXFileName
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
            print("[NAV] applyLocationType=Real")
            LocationService.shared.setProvider(RealGPSProvider(locationService: locationService))
        case .file:
            guard let url = DevToolsSettings.shared.selectedGPXFileURL else {
                // 모순 상태 — Real로 fallback
                print("[NAV] applyLocationType=File but no file → Real로 fallback")
                DevToolsSettings.shared.validateSelection()
                LocationService.shared.setProvider(RealGPSProvider(locationService: locationService))
                return
            }
            print("[NAV] applyLocationType=File (\(url.lastPathComponent))")
            LocationService.shared.setProvider(FileGPSProvider(gpxFileURL: url))
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

        mapViewController.showPOIMarker(for: place, zoomIn: true)

        if let existing = poiDetailDrawer {
            existing.update(with: place)
            return
        }

        presentPOIDetail(place) { [weak self] place in
            self?.dismissIntermediateDrawers {
                self?.showRoutePreview(to: place)
            }
        }
    }

    private func showPOIDetailFromDrawer(_ place: Place) {
        guard currentDrawer != nil else { return }

        mapViewController.showPOIMarker(for: place)

        if let existing = poiDetailDrawer {
            existing.update(with: place)
            return
        }

        presentPOIDetail(place) { [weak self] place in
            self?.dismissIntermediateDrawers {
                self?.showRoutePreview(to: place)
            }
        }
    }

    private func presentPOIDetail(
        _ place: Place,
        onRoute: @escaping (Place) -> Void
    ) {
        let detailVC = POIDetailViewController(place: place)
        poiDetailDrawer = detailVC

        detailVC.onRouteTapped = { place in
            onRoute(place)
        }

        detailVC.onClose = { [weak self] in
            self?.dismissPOIDetailWithCleanup()
        }

        drawerManager.pushDrawer(
            detailVC,
            detents: standardDetents(),
            initialDetent: homeInitialDetent()
        )
    }

    private func dismissSearchResultDrawerWithCleanup() {
        poiDetailDrawer = nil
        currentDrawer = nil
        lastSearchQuery = ""
        mapViewController.clearSearchResults()
        mapViewController.onAnnotationSelected = nil
        mapViewController.onRegionChanged = nil
        restoreHomeDrawer()
    }

    private func dismissPOIDetailWithCleanup() {
        poiDetailDrawer = nil
        mapViewController.clearPOIMarker()
        drawerManager.popDrawer()
    }

    private func dismissAllDrawers(completion: (() -> Void)? = nil) {
        currentDrawer = nil
        poiDetailDrawer = nil
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
            self?.showGPXFileList()
        }

        devToolsVC.onSelectGPXFile = { [weak self] in
            self?.showGPXFileList()
        }

        navigationController.pushViewController(devToolsVC, animated: true)
    }

    private func showGPXFileList() {
        let fileListVC = GPXFileListViewController()

        fileListVC.onDismiss = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }

        // 파일 탭 시 File 모드로 자동 전환 + 선택 저장 + 뒤로
        fileListVC.onSelectFile = { [weak self] record in
            DevToolsSettings.shared.setLocationType(.file)
            DevToolsSettings.shared.setSelectedGPXFileName(record.fileName)
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
        poiDetailDrawer = nil
        completion?()
    }

    // MARK: - Search Flow

    private func searchCategory(_ category: SearchCategory) {
        let region = mapViewController.mapView.region

        Task {
            do {
                let results = try await searchService.searchCategory(
                    category,
                    region: region,
                    regionMode: .biased
                )
                showSearchResults(results, query: category.name)
            } catch {
                print("[AppCoordinator] Category search failed: \(error.localizedDescription)")
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
        poiDetailDrawer = nil

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
               let existing = self?.poiDetailDrawer {
                existing.update(with: place)
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
                print("[AppCoordinator] Research failed: \(error.localizedDescription)")
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
        destinationAddress: String? = nil
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
            destinationName: destinationName
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
            self?.startVirtualDrive(with: route, transportMode: transportMode)
        }

        // Clear intermediate state and replace stack
        currentDrawer = nil
        poiDetailDrawer = nil
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

        // GPS publisher / locationSource / recordingMode 결정
        let gpsPublisher: AnyPublisher<GPSData, Never>
        let locationSource: AnyPublisher<CLLocation, Never>
        let recordingMode: GPXRecorder.RecordingMode

        if forceSimul {
            // 가상 주행: 별도 driver 생성, lifecycle은 안내 종료까지
            print("[NAV] GPS=Simul (가상 주행)")
            let driver = VirtualDriveDriver()
            driver.start(polyline: route.polylineCoordinates, transportMode: transportMode)
            activeVirtualDriveDriver = driver

            gpsPublisher = driver.gpsPublisher
            locationSource = driver.locationPublisher
            recordingMode = .simul
        } else {
            // 일반 안내: LocationService.activeProvider (Real or File)가 이미 흐름
            let type = DevToolsSettings.shared.locationType.value
            print("[NAV] GPS=\(type.rawValue)")
            gpsPublisher = LocationService.shared.gpsPublisher.eraseToAnyPublisher()
            locationSource = LocationService.shared.locationPublisher.compactMap { $0 }.eraseToAnyPublisher()
            recordingMode = (type == .real) ? .real : .simul
        }

        // GPX 녹화 자동 시작 (armed 상태면)
        startGPXRecordingIfArmed(
            mode: recordingMode,
            originName: nil,
            destinationName: resolvedDestination.name,
            locationSource: locationSource
        )

        // 엔진 시작
        sessionManager.startNavigation(
            route: route,
            destination: resolvedDestination,
            transportMode: transportMode,
            gpsPublisher: gpsPublisher,
            source: .phone
        )

        // 주행 화면 생성 + 엔진 바인딩
        dismissAllDrawers { [weak self] in
            guard let self else { return }

            let navVC = NavigationViewController(route: route, transportMode: transportMode, destinationName: resolvedDestination.name)
            navVC.bind(to: self.sessionManager.guidePublisher)
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
        finishGPXRecordingIfRecording()

        sessionManager.stopNavigation()

        // 가상 주행 driver 정리 (있으면)
        activeVirtualDriveDriver?.stop()
        activeVirtualDriveDriver = nil

        navigationMapViewController = nil
        mapViewController.mapView.setUserTrackingMode(.follow, animated: false)
        navigationController.popToViewController(homeViewController, animated: true)
    }

    // MARK: - GPX Recording (1회 자동 녹화)

    /// armed 상태면 자동으로 녹화 시작
    /// - locationSource: 좌표 소스 (Real/File: LocationService, 가상주행: driver.locationPublisher)
    private func startGPXRecordingIfArmed(
        mode: GPXRecorder.RecordingMode,
        originName: String?,
        destinationName: String?,
        locationSource: AnyPublisher<CLLocation, Never>
    ) {
        let recorder = GPXRecorder.shared
        print("[GPX-DEBUG] startGPXRecordingIfArmed() — isArmed=\(recorder.isArmed) mode=\(mode.rawValue)")
        guard recorder.isArmed else { return }

        recorder.startRecording(
            mode: mode,
            originName: originName,
            destinationName: destinationName,
            locationSource: locationSource
        )
    }

    /// 녹화 중이면 종료 + 파일 저장 + DataService 기록
    private func finishGPXRecordingIfRecording() {
        let recorder = GPXRecorder.shared
        print("[GPX-DEBUG] finishGPXRecordingIfRecording() — state=\(recorder.statePublisher.value)")
        guard recorder.statePublisher.value == .recording else { return }

        let result = recorder.stopRecording()

        // DataService 저장
        if let result {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: result.fileURL.path)[.size] as? Int64) ?? 0
            let relativePath = "GPXRecordings/\(result.fileURL.lastPathComponent)"
            DataService.shared.saveGPXRecord(
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
            print("[GPX-DEBUG] DataService.saveGPXRecord OK — \(result.fileURL.lastPathComponent) points=\(result.pointCount) dist=\(Int(result.distance))m")
        } else {
            print("[GPX-DEBUG] DataService.saveGPXRecord skipped — result=nil")
        }
    }

    // MARK: - Virtual Drive Flow

    private func startVirtualDrive(with route: Route, transportMode: TransportMode = .automobile) {
        // 가상 주행은 Location Type 설정 무시 — 항상 SimulGPS
        startNavigation(with: route, transportMode: transportMode, forceSimul: true)
    }

    private func cleanUpNavigationUI() {
        navigationMapViewController = nil
        mapViewController.mapView.setUserTrackingMode(.follow, animated: false)
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
