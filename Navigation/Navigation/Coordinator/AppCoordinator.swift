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
    private let searchService: SearchProviding
    private let routeService: RouteProviding
    private let sessionManager = NavigationSessionManager.shared

    private var mapViewController: MapViewController!
    private var homeViewController: HomeViewController!
    private var homeViewModel: HomeViewModel!
    private var homeDrawerVC: HomeDrawerViewController?
    private var currentDrawer: SearchResultDrawerViewController?
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
        let lbs = LBSServiceProvider.shared
        self.searchService = lbs.search
        self.routeService = lbs.route
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

        homeVC.onSearchBarTapped = { [weak self] in
            self?.showSearch()
        }

        homeVC.onSettingsTapped = { [weak self] in
            self?.showSettings()
        }

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
        drawerVC.onRecentSearchTapped = { [weak self] history in
            self?.showRoutePreviewForHistory(history)
        }

        let containerView = navigationController.view!
        let maxHeight = drawerMaxHeight(in: containerView)

        drawerManager.setPrimary(
            .home(drawerVC),
            detents: [
                .absolute(200, id: "small"),
                .absolute(maxHeight * 0.5, id: "drawerMedium"),
                .absolute(maxHeight, id: "drawerLarge"),
            ],
            initialDetent: .absolute(maxHeight * 0.5, id: "drawerMedium")
        )
    }

    private func dismissHomeDrawer(animated: Bool = false, completion: (() -> Void)? = nil) {
        drawerManager.hideAll(animated: animated)
        completion?()
    }

    // MARK: - POI Detail Flow

    private func showPOIDetail(_ place: Place) {
        guard navigationController.topViewController === homeViewController else { return }

        // 이미 POI 시트가 떠있으면 내용만 업데이트
        if let existing = poiDetailDrawer {
            existing.update(with: place)
            return
        }

        presentPOIDetail(place, from: navigationController) { [weak self] place in
            // 홈 → POI 상세 → 경로: 중간 드로어만 dismiss
            self?.dismissIntermediateDrawers {
                self?.showRoutePreview(to: place)
            }
        }
    }

    private func showPOIDetailFromDrawer(_ place: Place) {
        guard let drawer = currentDrawer else { return }

        // 이미 POI 시트가 떠있으면 내용만 업데이트
        if let existing = poiDetailDrawer {
            existing.update(with: place)
            return
        }

        presentPOIDetail(place, from: drawer) { [weak self] place in
            // 검색결과 → POI 상세 → 경로: 중간 드로어만 dismiss
            self?.dismissIntermediateDrawers {
                self?.showRoutePreview(to: place)
            }
        }
    }

    private func presentPOIDetail(
        _ place: Place,
        from presenter: UIViewController,
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

        if let sheet = detailVC.sheetPresentationController {
            let poiDetent = UISheetPresentationController.Detent.custom(
                identifier: .init("poiDetail")
            ) { _ in 320 }
            sheet.detents = [poiDetent]
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .init("poiDetail")
            sheet.delegate = self
        }

        presenter.present(detailVC, animated: true)
        let containerView = navigationController.view!
        homeViewController.updateMapControlBottomOffset(320)
        homeViewController.updateMapInsets(
            top: mapTopInset(in: containerView),
            bottom: 320
        )
    }

    private func dismissPOIDetail(animated: Bool = false, completion: (() -> Void)? = nil) {
        guard let drawer = poiDetailDrawer else {
            completion?()
            return
        }
        drawer.dismiss(animated: animated) { [weak self] in
            self?.poiDetailDrawer = nil
            completion?()
        }
    }

    private func dismissSearchResultDrawerWithCleanup() {
        poiDetailDrawer = nil
        navigationController.dismiss(animated: true) { [weak self] in
            self?.currentDrawer = nil
            self?.mapViewController.clearSearchResults()
            self?.mapViewController.onAnnotationSelected = nil
            // drawerManager.onHeightChanged handles inset restoration
        }
    }

    private func dismissPOIDetailWithCleanup() {
        poiDetailDrawer?.dismiss(animated: true) { [weak self] in
            self?.poiDetailDrawer = nil
        }
    }

    private func dismissAllDrawers(animated: Bool = false, completion: (() -> Void)? = nil) {
        // Dismiss any modal sheets (SearchResult, RoutePreview, POIDetail still use modal in Phase 2)
        navigationController.dismiss(animated: animated) { [weak self] in
            self?.currentDrawer = nil
            self?.poiDetailDrawer = nil
            self?.routePreviewDrawer = nil
            self?.mapViewController.clearSearchResults()
            self?.mapViewController.clearRoutes()
            self?.mapViewController.clearDestination()
            self?.mapViewController.onAnnotationSelected = nil
            completion?()
        }
        // Hide the child VC drawer
        drawerManager.hideAll(animated: animated)
    }

    /// Top map inset: below search bar (safeArea + spacing + searchBarHeight + spacing)
    private func mapTopInset(in containerView: UIView) -> CGFloat {
        return containerView.safeAreaInsets.top + Theme.Spacing.sm + 48 + Theme.Spacing.sm
    }

    /// Maximum drawer height (below search bar with margin)
    private func drawerMaxHeight(in containerView: UIView) -> CGFloat {
        let searchBarBottom = mapTopInset(in: containerView)
        return containerView.bounds.height - searchBarBottom - Theme.Spacing.sm
    }

    /// Drawer height for a given detent identifier
    private func drawerHeight(for detentId: UISheetPresentationController.Detent.Identifier?, in containerView: UIView) -> CGFloat {
        switch detentId {
        case Self.smallDetentId:
            return 200
        case Self.mediumDetentId:
            return drawerMaxHeight(in: containerView) * 0.5
        default:
            return drawerMaxHeight(in: containerView)
        }
    }

    // MARK: - Drawer Detent Identifiers

    private static let smallDetentId = UISheetPresentationController.Detent.Identifier("small")
    private static let mediumDetentId = UISheetPresentationController.Detent.Identifier("drawerMedium")
    private static let largeDetentId = UISheetPresentationController.Detent.Identifier("drawerLarge")

    /// Unified sheet detent configuration shared by home drawer and search result drawer
    private func configureSheetDetents(for viewController: UIViewController) {
        guard let sheet = viewController.sheetPresentationController else { return }

        let smallDetent = UISheetPresentationController.Detent.custom(identifier: Self.smallDetentId) { _ in
            return 200
        }
        let mediumDetent = UISheetPresentationController.Detent.custom(identifier: Self.mediumDetentId) { [weak self] _ in
            guard let view = self?.navigationController.view else { return 400 }
            return (self?.drawerMaxHeight(in: view) ?? 400) * 0.5
        }
        let largeDetent = UISheetPresentationController.Detent.custom(identifier: Self.largeDetentId) { [weak self] _ in
            guard let view = self?.navigationController.view else { return 600 }
            return self?.drawerMaxHeight(in: view) ?? 600
        }

        sheet.detents = [smallDetent, mediumDetent, largeDetent]
        sheet.selectedDetentIdentifier = Self.mediumDetentId
        sheet.prefersGrabberVisible = true
        sheet.largestUndimmedDetentIdentifier = Self.largeDetentId
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.delegate = self
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
            // Cap map control buttons at medium height when drawer is at large
            let maxHeight = self.drawerMaxHeight(in: containerView)
            let effectiveHeight = min(height, maxHeight * 0.5)
            self.homeViewController.updateMapControlBottomOffset(effectiveHeight)
            self.homeViewController.updateMapInsets(
                top: self.mapTopInset(in: containerView),
                bottom: height
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
        dismissAllDrawers(animated: false) { [weak self] in
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
        drawerManager.hideAll()

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
        let hasModal = routePreviewDrawer != nil || poiDetailDrawer != nil || currentDrawer != nil

        if hasModal {
            navigationController.dismiss(animated: false) { [weak self] in
                if self?.routePreviewDrawer != nil {
                    self?.routePreviewDrawer = nil
                    self?.mapViewController.clearRoutes()
                    self?.mapViewController.clearDestination()
                }
                if self?.currentDrawer != nil {
                    self?.currentDrawer = nil
                    self?.mapViewController.clearSearchResults()
                    self?.mapViewController.onAnnotationSelected = nil
                }
                self?.poiDetailDrawer = nil
                completion?()
            }
        } else {
            completion?()
        }
    }

    // MARK: - Search Flow

    private func showSearch() {
        let presentSearchVC = { [weak self] in
            guard let self else { return }

            let mapRegion = self.mapViewController.mapView.region

            let searchViewModel = SearchViewModel(
                searchService: self.searchService
            )
            searchViewModel.updateSearchRegion(mapRegion)
            let searchVC = SearchViewController(viewModel: searchViewModel)
            searchVC.modalPresentationStyle = .fullScreen

            searchVC.onDismiss = { [weak self] in
                self?.navigationController.dismiss(animated: true) {
                    self?.drawerManager.showPrimary()
                }
            }

            searchVC.onSearchResults = { [weak self] results in
                self?.navigationController.dismiss(animated: true) {
                    self?.showSearchResults(results)
                }
            }

            // 드로어 숨기고 검색 VC present
            self.drawerManager.hideAll(animated: false)
            self.navigationController.present(searchVC, animated: false)
        }

        // Dismiss any modal drawers, then present search
        if currentDrawer != nil || poiDetailDrawer != nil {
            navigationController.dismiss(animated: false) { [weak self] in
                self?.currentDrawer = nil
                self?.poiDetailDrawer = nil
                self?.mapViewController.clearSearchResults()
                self?.mapViewController.onAnnotationSelected = nil
                presentSearchVC()
            }
        } else {
            presentSearchVC()
        }
    }

    private func showSearchResults(_ results: [Place]) {
        // Show markers on map
        mapViewController.showSearchResults(results)

        // Create search result drawer
        let drawerVC = SearchResultDrawerViewController()
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

        // Present as sheet from navigationController (no asyncAfter needed)
        configureSheetDetents(for: drawerVC)
        navigationController.present(drawerVC, animated: true)
        let containerView = navigationController.view!
        let initialHeight = drawerHeight(for: Self.mediumDetentId, in: containerView)
        homeViewController.updateMapControlBottomOffset(initialHeight)
        homeViewController.updateMapInsets(top: mapTopInset(in: containerView), bottom: initialHeight)
    }

    private func dismissSearchResultDrawer(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let drawer = currentDrawer else {
            completion?()
            return
        }
        drawer.dismiss(animated: animated) { [weak self] in
            self?.currentDrawer = nil
            self?.mapViewController.clearSearchResults()
            self?.mapViewController.onAnnotationSelected = nil
            completion?()
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

    private static let routePreviewCompactDetentId =
        UISheetPresentationController.Detent.Identifier("routePreviewCompact")
    private static let routePreviewExpandedDetentId =
        UISheetPresentationController.Detent.Identifier("routePreviewExpanded")

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

        // Configure sheet detents
        if let sheet = drawerVC.sheetPresentationController {
            let compactDetent = UISheetPresentationController.Detent.custom(
                identifier: Self.routePreviewCompactDetentId
            ) { _ in 200 }
            let expandedDetent = UISheetPresentationController.Detent.custom(
                identifier: Self.routePreviewExpandedDetentId
            ) { _ in 420 }

            sheet.detents = [compactDetent, expandedDetent]
            sheet.selectedDetentIdentifier = Self.routePreviewExpandedDetentId
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = Self.routePreviewExpandedDetentId
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.delegate = self
        }

        // Present from navigationController (no asyncAfter needed)
        navigationController.present(drawerVC, animated: true)
        let containerView = navigationController.view!
        homeViewController.updateMapControlBottomOffset(420)
        homeViewController.updateMapInsets(
            top: mapTopInset(in: containerView),
            bottom: 420
        )
    }

    private func dismissRoutePreviewDrawerWithCleanup() {
        navigationController.dismiss(animated: true) { [weak self] in
            self?.routePreviewDrawer = nil
            self?.mapViewController.clearRoutes()
            self?.mapViewController.clearDestination()
        }
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
        dismissAllDrawers(animated: false) { [weak self] in
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
        dismissAllDrawers(animated: false) { [weak self] in
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
            if viewController === homeViewController {
                if homeDrawerVC == nil {
                    presentHomeDrawer()
                } else {
                    drawerManager.showPrimary()
                }
            }
        }
    }
}

// MARK: - UISheetPresentationControllerDelegate

extension AppCoordinator: UISheetPresentationControllerDelegate {

    nonisolated func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        MainActor.assumeIsolated {
            let detentId = sheetPresentationController.selectedDetentIdentifier
            let containerView = navigationController.view!

            // Route preview drawer uses its own detent heights
            if sheetPresentationController.presentedViewController is RoutePreviewDrawerViewController {
                let height: CGFloat = (detentId == Self.routePreviewCompactDetentId) ? 200 : 420
                homeViewController.updateMapControlBottomOffset(height)
                homeViewController.updateMapInsets(top: mapTopInset(in: containerView), bottom: height)
                return
            }

            // Cap at medium for map control buttons (don't move higher at large)
            let effectiveDetent: UISheetPresentationController.Detent.Identifier? =
                (detentId == Self.largeDetentId) ? Self.mediumDetentId : detentId
            let height = drawerHeight(for: effectiveDetent, in: containerView)

            homeViewController.updateMapControlBottomOffset(height)
            homeViewController.updateMapInsets(top: mapTopInset(in: containerView), bottom: height)
        }
    }

    nonisolated func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        MainActor.assumeIsolated {
            let dismissed = presentationController.presentedViewController

            if dismissed is RoutePreviewDrawerViewController {
                // 경로 미리보기 드로어 스와이프 dismiss
                routePreviewDrawer = nil
                mapViewController.clearRoutes()
                mapViewController.clearDestination()
                // 홈 드로어 인셋 복원
                let containerView = navigationController.view!
                let height = drawerHeight(for: Self.mediumDetentId, in: containerView)
                homeViewController.updateMapControlBottomOffset(height)
                homeViewController.updateMapInsets(top: mapTopInset(in: containerView), bottom: height)
                return
            }

            if dismissed is POIDetailViewController {
                // POI 상세 스와이프 dismiss → 이전 시트(홈/검색결과)가 자동 복귀
                poiDetailDrawer = nil
                return
            }

            if dismissed is SearchResultDrawerViewController {
                // 검색결과 드로어 스와이프 dismiss → 홈 드로어가 자동 복귀
                currentDrawer = nil
                mapViewController.clearSearchResults()
                mapViewController.onAnnotationSelected = nil
                // 홈 드로어는 아래에 살아있으므로 presentHomeDrawer 불필요
            }
        }
    }
}
