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

    // MARK: - iPhone-only Navigation Services

    private var navigationViewController: NavigationViewController?
    private var mapInterpolator: MapInterpolator?
    private var mapCamera: MapCamera?
    private var turnPointPopupService: TurnPointPopupService?

    // MARK: - Navigation Map (ephemeral, created per session)

    private var navigationMapViewController: MapViewController?

    // MARK: - Virtual Drive / GPX

    private var virtualDriveEngine: VirtualDriveEngine?
    private var gpxSimulator: GPXSimulator?
    private var simulationCancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(window: UIWindow) {
        self.window = window
        self.locationService = .shared
        self.navigationController = UINavigationController()
        self.navigationController.isNavigationBarHidden = true
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
            initialDetent: homeInitialDetent()
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
                    if self?.navigationViewController != nil {
                        self?.cleanUpNavigationUI()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func handleCarPlayNavigationStarted() {
        guard let session = sessionManager.activeSessionPublisher.value else { return }

        // If already showing navigation, skip
        guard navigationViewController == nil else { return }

        // Dismiss all drawers (home, search, POI, route preview)
        dismissAllDrawers { [weak self] in
            self?.presentNavigationFromSession(session)
        }
    }

    private func presentNavigationFromSession(_ session: NavigationSession) {
        let camera = MapCamera()
        let interpolator = MapInterpolator(mapCamera: camera)
        let popup = TurnPointPopupService(
            guidanceEngine: session.guidanceEngine,
            locationService: locationService
        )

        self.mapCamera = camera
        self.mapInterpolator = interpolator
        self.turnPointPopupService = popup

        // Create a fresh map for navigation (home map stays untouched)
        let navMapVC = createNavigationMapVC()
        self.navigationMapViewController = navMapVC
        navMapVC.configureForNavigation()
        navMapVC.showSingleRoute(session.route)

        // Create NavigationViewModel with shared GuidanceEngine
        let navViewModel = NavigationViewModel(
            guidanceEngine: session.guidanceEngine,
            mapInterpolator: interpolator,
            turnPointPopupService: popup,
            locationService: locationService,
            mapCamera: camera
        )

        let navVC = NavigationViewController(
            mode: .realNavigation,
            mapViewController: navMapVC,
            viewModel: navViewModel,
            turnPointPopupService: popup
        )
        self.navigationViewController = navVC

        navVC.onDismiss = { [weak self] in
            self?.dismissNavigation()
        }

        interpolator.start(mapViewController: navMapVC)
        navViewModel.startNavigation(with: session.route)

        navigationController.pushViewController(navVC, animated: true)
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

        devToolsVC.onSelectFileForPlayback = { [weak self] in
            self?.showGPXFileListForPlayback()
        }

        navigationController.pushViewController(devToolsVC, animated: true)
    }

    private func showGPXFileList() {
        let fileListVC = GPXFileListViewController()

        fileListVC.onDismiss = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }

        fileListVC.onSelectFile = { [weak self] record in
            self?.startGPXPlayback(record: record)
        }

        navigationController.pushViewController(fileListVC, animated: true)
    }

    private func showGPXFileListForPlayback() {
        showGPXFileList()
    }

    // MARK: - Favorite / History Quick Navigate

    private func showRoutePreviewForFavorite(_ favorite: FavoritePlace) {
        dismissIntermediateDrawers { [weak self] in
            guard let self else { return }
            let destination = CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude)
            let userCoordinate = self.locationService.bestAvailableLocation?.coordinate
                ?? self.mapViewController.mapView.centerCoordinate

            self.mapViewController.showDestination(coordinate: destination, title: favorite.name, subtitle: favorite.address)
            self.presentRoutePreviewDrawer(origin: userCoordinate, destination: destination, destinationName: favorite.name)
        }
    }

    private func showRoutePreviewForHistory(_ history: SearchHistory) {
        dismissIntermediateDrawers { [weak self] in
            guard let self else { return }
            let destination = history.coordinate
            let userCoordinate = self.locationService.bestAvailableLocation?.coordinate
                ?? self.mapViewController.mapView.centerCoordinate

            self.mapViewController.showDestination(coordinate: destination, title: history.placeName, subtitle: history.address)
            self.presentRoutePreviewDrawer(origin: userCoordinate, destination: destination, destinationName: history.placeName)
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
            destinationName: place.name
        )
    }

    // MARK: - Route Preview Drawer

    private func presentRoutePreviewDrawer(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationName: String?
    ) {
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

    private func startNavigation(with route: Route, destination: Place? = nil, transportMode: TransportMode = .automobile) {
        // 1. Resolve destination
        let lastCoord = route.polylineCoordinates.last ?? CLLocationCoordinate2D()
        let resolvedDestination = destination
            ?? Place(name: nil, coordinate: lastCoord, address: nil, phoneNumber: nil, url: nil, category: nil, providerRawData: nil)

        // 2. Start shared navigation session via SessionManager
        sessionManager.startNavigation(
            route: route,
            destination: resolvedDestination,
            source: .phone
        )

        guard let session = sessionManager.activeSessionPublisher.value else { return }

        // 3. Dismiss all drawers first
        dismissAllDrawers { [weak self] in
            guard let self else { return }

            // 4. Create iPhone-only services
            let camera = MapCamera()
            camera.transportMode = transportMode
            let interpolator = MapInterpolator(mapCamera: camera)
            let popup = TurnPointPopupService(
                guidanceEngine: session.guidanceEngine,
                locationService: self.locationService
            )

            self.mapCamera = camera
            self.mapInterpolator = interpolator
            self.turnPointPopupService = popup

            // 5. Create a fresh map for navigation (home map stays untouched)
            let navMapVC = self.createNavigationMapVC()
            self.navigationMapViewController = navMapVC
            navMapVC.configureForNavigation()
            navMapVC.showSingleRoute(route)

            // 6. Create NavigationViewModel with shared GuidanceEngine
            let navViewModel = NavigationViewModel(
                guidanceEngine: session.guidanceEngine,
                mapInterpolator: interpolator,
                turnPointPopupService: popup,
                locationService: self.locationService,
                mapCamera: camera
            )

            // 7. Create NavigationViewController
            let navVC = NavigationViewController(
                mode: .realNavigation,
                mapViewController: navMapVC,
                viewModel: navViewModel,
                turnPointPopupService: popup
            )
            self.navigationViewController = navVC

            navVC.onDismiss = { [weak self] in
                self?.dismissNavigation()
            }

            // 8. Start iPhone-only services
            interpolator.start(mapViewController: navMapVC)
            navViewModel.startNavigation(with: route, transportMode: transportMode)

            // 9. Push NavigationVC
            self.navigationController.pushViewController(navVC, animated: true)
        }
    }

    private func dismissNavigation() {
        // Clean up iPhone-only UI first (before stop triggers observer)
        cleanUpNavigationUI()

        // Stop shared navigation session (notifies CarPlay too)
        sessionManager.stopNavigation()
    }

    // MARK: - Virtual Drive Flow

    private func startVirtualDrive(with route: Route, transportMode: TransportMode = .automobile) {
        dismissAllDrawers { [weak self] in
            guard let self else { return }

            let engine = VirtualDriveEngine()
            engine.load(route: route)
            self.virtualDriveEngine = engine

            let navMapVC = self.createNavigationMapVC()
            self.navigationMapViewController = navMapVC

            let camera = MapCamera()
            camera.transportMode = transportMode
            let interpolator = MapInterpolator(mapCamera: camera)
            self.mapCamera = camera
            self.mapInterpolator = interpolator

            navMapVC.configureForNavigation()
            navMapVC.showSingleRoute(route)
            interpolator.start(mapViewController: navMapVC)

            // Feed simulated locations into interpolator
            self.simulationCancellables.removeAll()
            engine.simulatedLocationPublisher
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] location in
                    let heading = self?.virtualDriveEngine?.simulatedHeadingPublisher.value ?? 0
                    self?.mapInterpolator?.updateTarget(location: location, heading: heading)
                }
                .store(in: &self.simulationCancellables)

            let navVC = NavigationViewController(
                mode: .virtualDrive(engine: engine),
                mapViewController: navMapVC
            )
            self.navigationViewController = navVC
            navVC.onDismiss = { [weak self] in self?.stopVirtualDrive() }

            self.navigationController.pushViewController(navVC, animated: true)
            engine.play()
        }
    }

    private func stopVirtualDrive() {
        simulationCancellables.removeAll()
        virtualDriveEngine?.stop()
        virtualDriveEngine = nil
        navigationViewController = nil

        mapInterpolator?.stop()
        mapInterpolator = nil
        mapCamera = nil
        navigationMapViewController = nil

        mapViewController.mapView.setUserTrackingMode(.follow, animated: false)
        navigationController.popToViewController(homeViewController, animated: true)
    }

    // MARK: - GPX Playback Flow

    private func startGPXPlayback(record: GPXRecord) {
        let simulator = GPXSimulator()
        guard simulator.load(gpxFileURL: record.fileURL) else { return }
        self.gpxSimulator = simulator

        LocationService.shared.startLocationOverride(from: simulator.simulatedLocationPublisher)

        let navMapVC = createNavigationMapVC()
        self.navigationMapViewController = navMapVC

        // Show GPX track as polyline overlay
        let parser = GPXParser()
        let locations = parser.parse(fileURL: record.fileURL)
        if locations.count >= 2 {
            let coordinates = locations.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            navMapVC.addOverlay(polyline)
        }

        let navVC = NavigationViewController(
            mode: .gpxPlayback(simulator: simulator),
            mapViewController: navMapVC
        )
        self.navigationViewController = navVC
        navVC.onDismiss = { [weak self] in self?.stopGPXPlayback() }

        navigationController.pushViewController(navVC, animated: true)
        simulator.play()
    }

    private func stopGPXPlayback() {
        simulationCancellables.removeAll()
        gpxSimulator?.stop()
        gpxSimulator = nil
        navigationViewController = nil

        LocationService.shared.stopLocationOverride()
        navigationMapViewController = nil

        mapViewController.mapView.setUserTrackingMode(.follow, animated: false)
        navigationController.popToViewController(homeViewController, animated: true)
    }

    private func cleanUpNavigationUI() {
        // 1. Stop iPhone-only services
        mapInterpolator?.stop()
        turnPointPopupService?.reset()

        // 2. Discard navigation map (home map was never touched)
        navigationMapViewController = nil

        // 3. Recenter home map to current location
        mapViewController.mapView.setUserTrackingMode(.follow, animated: false)

        // 4. Pop to HomeVC (delegate auto-presents home drawer)
        navigationController.popToViewController(homeViewController, animated: true)

        // 5. Clear iPhone-only references
        navigationViewController = nil
        mapInterpolator = nil
        mapCamera = nil
        turnPointPopupService = nil
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
