import UIKit
import MapKit
import Combine
import CoreLocation

final class AppCoordinator: Coordinator {

    // MARK: - Coordinator

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []

    // MARK: - Properties

    private let window: UIWindow
    private let locationService: LocationService
    private let searchService: SearchService
    private let routeService: RouteService
    private let sessionManager = NavigationSessionManager.shared

    private var mapViewController: MapViewController!
    private var homeViewController: HomeViewController!
    private var currentDrawer: SearchResultDrawerViewController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - iPhone-only Navigation Services

    private var navigationViewController: NavigationViewController?
    private var mapInterpolator: MapInterpolator?
    private var mapCamera: MapCamera?
    private var turnPointPopupService: TurnPointPopupService?

    // MARK: - Virtual Drive

    private var virtualDriveEngine: VirtualDriveEngine?
    private var virtualDriveControlView: VirtualDriveControlView?

    // MARK: - Init

    init(window: UIWindow) {
        self.window = window
        self.locationService = .shared
        self.searchService = SearchService()
        self.routeService = RouteService()
        self.navigationController = UINavigationController()
        self.navigationController.isNavigationBarHidden = true
    }

    // MARK: - Start

    func start() {
        let mapVC = MapViewController(locationService: locationService)
        self.mapViewController = mapVC

        let homeViewModel = HomeViewModel(locationService: locationService)
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

        homeVC.onFavoriteTapped = { [weak self] favorite in
            self?.showRoutePreviewForFavorite(favorite)
        }

        homeVC.onRecentSearchTapped = { [weak self] history in
            self?.showRoutePreviewForHistory(history)
        }

        navigationController.setViewControllers([homeVC], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        bindSessionManager()
        setupDebugOverlayObserver()
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
            } else {
                self?.mapViewController.hideDebugOverlay()
            }
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

        // Dismiss any presented VCs (search, drawer)
        navigationController.dismiss(animated: false)
        currentDrawer = nil

        // Pop to home if needed
        if navigationController.topViewController !== homeViewController {
            navigationController.popToViewController(homeViewController, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.returnMapToHome()
                self?.presentNavigationFromSession(session)
            }
        } else {
            presentNavigationFromSession(session)
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

        // Remove map from Home
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // Configure map for navigation
        mapViewController.clearAll()
        mapViewController.configureForNavigation()
        mapViewController.showSingleRoute(session.route)

        // Create NavigationViewModel with shared GuidanceEngine
        let navViewModel = NavigationViewModel(
            guidanceEngine: session.guidanceEngine,
            mapInterpolator: interpolator,
            turnPointPopupService: popup,
            locationService: locationService,
            mapCamera: camera
        )

        let navVC = NavigationViewController(
            viewModel: navViewModel,
            mapViewController: mapViewController,
            turnPointPopupService: popup
        )
        self.navigationViewController = navVC

        navVC.onDismiss = { [weak self] in
            self?.dismissNavigation()
        }

        interpolator.start(mapViewController: mapViewController)
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
        let destination = CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude)
        let userCoordinate = locationService.locationPublisher.value?.coordinate
            ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

        mapViewController.showDestination(coordinate: destination, title: favorite.name, subtitle: favorite.address)
        moveMapToRoutePreview(origin: userCoordinate, destination: destination, destinationName: favorite.name)
    }

    private func showRoutePreviewForHistory(_ history: SearchHistory) {
        let destination = history.coordinate
        let userCoordinate = locationService.locationPublisher.value?.coordinate
            ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

        mapViewController.showDestination(coordinate: destination, title: history.placeName, subtitle: history.address)
        moveMapToRoutePreview(origin: userCoordinate, destination: destination, destinationName: history.placeName)
    }

    // MARK: - Search Flow

    private func showSearch() {
        let searchViewModel = SearchViewModel(
            searchService: searchService
        )
        let searchVC = SearchViewController(viewModel: searchViewModel)
        searchVC.modalPresentationStyle = .fullScreen

        searchVC.onDismiss = { [weak self] in
            self?.navigationController.dismiss(animated: true)
        }

        searchVC.onSearchResults = { [weak self] results in
            self?.navigationController.dismiss(animated: true) {
                self?.showSearchResults(results)
            }
        }

        navigationController.present(searchVC, animated: true)
    }

    private func showSearchResults(_ results: [MKMapItem]) {
        // Show markers on map
        mapViewController.showSearchResults(results)

        // Create drawer
        let drawerVC = SearchResultDrawerViewController()
        drawerVC.updateResults(results)
        currentDrawer = drawerVC

        // Drawer → Map sync: item tapped → show route preview
        drawerVC.onItemSelected = { [weak self] mapItem, _ in
            self?.showRoutePreview(to: mapItem)
        }

        // Drawer → Map sync: scroll changes focused annotation
        drawerVC.onFocusedIndexChanged = { [weak self] index in
            self?.mapViewController.focusAnnotation(at: index)
        }

        // Map → Drawer sync: annotation tapped → scroll drawer
        mapViewController.onAnnotationSelected = { [weak self] index in
            self?.currentDrawer?.scrollToIndex(index)
        }

        // Present as sheet
        if let sheet = drawerVC.sheetPresentationController {
            let smallDetent = UISheetPresentationController.Detent.custom(identifier: .init("small")) { _ in
                return 200
            }
            let mediumDetent = UISheetPresentationController.Detent.medium()
            let largeDetent = UISheetPresentationController.Detent.large()

            sheet.detents = [smallDetent, mediumDetent, largeDetent]
            sheet.selectedDetentIdentifier = .init("small")
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = largeDetent.identifier
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }

        navigationController.present(drawerVC, animated: true)
    }

    // MARK: - Route Preview Flow

    private func showRoutePreview(to mapItem: MKMapItem) {
        // Dismiss drawer
        currentDrawer?.dismiss(animated: true) { [weak self] in
            self?.currentDrawer = nil
        }

        // Clear search markers
        mapViewController.clearSearchResults()

        // Show destination pin
        let coordinate = mapItem.location.coordinate
        let subtitle = mapItem.address?.shortAddress ?? mapItem.address?.fullAddress
        mapViewController.showDestination(
            coordinate: coordinate,
            title: mapItem.name,
            subtitle: subtitle
        )

        // Get current user location
        let userCoordinate = locationService.locationPublisher.value?.coordinate
            ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780) // Seoul fallback

        // Move map to child of RoutePreviewVC
        moveMapToRoutePreview(
            origin: userCoordinate,
            destination: coordinate,
            destinationName: mapItem.name
        )
    }

    private func moveMapToRoutePreview(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationName: String?
    ) {
        // Remove map from Home
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // Create RoutePreview
        let routePreviewVM = RoutePreviewViewModel(
            routeService: routeService,
            origin: origin,
            destination: destination,
            destinationName: destinationName
        )

        let routePreviewVC = RoutePreviewViewController(
            viewModel: routePreviewVM,
            mapViewController: mapViewController
        )

        routePreviewVC.onDismiss = { [weak self] in
            self?.dismissRoutePreview()
        }

        routePreviewVC.onStartNavigation = { [weak self] route, transportMode in
            let mapItem = MKMapItem(
                location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
                address: nil
            )
            mapItem.name = destinationName
            self?.startNavigation(with: route, destination: mapItem, transportMode: transportMode)
        }

        routePreviewVC.onStartVirtualDrive = { [weak self] route, transportMode in
            self?.startVirtualDrive(with: route, transportMode: transportMode)
        }

        navigationController.pushViewController(routePreviewVC, animated: true)
    }

    private func dismissRoutePreview() {
        // Pop RoutePreviewVC
        navigationController.popViewController(animated: true)

        // Return map to Home
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.returnMapToHome()
        }
    }

    private func returnMapToHome() {
        // Remove map from any parent
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // Re-add to Home
        homeViewController.addChild(mapViewController)
        homeViewController.view.insertSubview(mapViewController.view, at: 0)
        mapViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mapViewController.view.topAnchor.constraint(equalTo: homeViewController.view.topAnchor),
            mapViewController.view.leadingAnchor.constraint(equalTo: homeViewController.view.leadingAnchor),
            mapViewController.view.trailingAnchor.constraint(equalTo: homeViewController.view.trailingAnchor),
            mapViewController.view.bottomAnchor.constraint(equalTo: homeViewController.view.bottomAnchor),
        ])

        mapViewController.didMove(toParent: homeViewController)
    }

    // MARK: - Navigation Flow

    private func startNavigation(with route: MKRoute, destination: MKMapItem? = nil, transportMode: TransportMode = .automobile) {
        // 1. Resolve destination
        let lastCoord = route.polyline.coordinates.last ?? CLLocationCoordinate2D()
        let resolvedDestination = destination
            ?? MKMapItem(location: CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude), address: nil)

        // 2. Start shared navigation session via SessionManager
        //    This creates GuidanceEngine, VoiceService, OffRouteDetector,
        //    configures location, and starts guidance.
        //    CarPlay will auto-detect via navigationCommandPublisher.
        sessionManager.startNavigation(
            route: route,
            destination: resolvedDestination,
            source: .phone
        )

        guard let session = sessionManager.activeSessionPublisher.value else { return }

        // 3. Create iPhone-only services
        let camera = MapCamera()
        camera.transportMode = transportMode
        let interpolator = MapInterpolator(mapCamera: camera)
        let popup = TurnPointPopupService(
            guidanceEngine: session.guidanceEngine,
            locationService: locationService
        )

        self.mapCamera = camera
        self.mapInterpolator = interpolator
        self.turnPointPopupService = popup

        // 4. Remove map from RoutePreviewVC
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // 5. Configure map for navigation mode
        mapViewController.clearAll()
        mapViewController.configureForNavigation()
        mapViewController.showSingleRoute(route)

        // 6. Create NavigationViewModel with shared GuidanceEngine
        let navViewModel = NavigationViewModel(
            guidanceEngine: session.guidanceEngine,
            mapInterpolator: interpolator,
            turnPointPopupService: popup,
            locationService: locationService,
            mapCamera: camera
        )

        // 7. Create NavigationViewController
        let navVC = NavigationViewController(
            viewModel: navViewModel,
            mapViewController: mapViewController,
            turnPointPopupService: popup
        )
        self.navigationViewController = navVC

        navVC.onDismiss = { [weak self] in
            self?.dismissNavigation()
        }

        // 8. Start iPhone-only services
        interpolator.start(mapViewController: mapViewController)
        navViewModel.startNavigation(with: route, transportMode: transportMode)

        // 9. Push NavigationVC (replaces RoutePreviewVC)
        navigationController.pushViewController(navVC, animated: true)
    }

    private func dismissNavigation() {
        // Clean up iPhone-only UI first (before stop triggers observer)
        cleanUpNavigationUI()

        // Stop shared navigation session (notifies CarPlay too)
        sessionManager.stopNavigation()
    }

    // MARK: - Virtual Drive Flow

    private func startVirtualDrive(with route: MKRoute, transportMode: TransportMode = .automobile) {
        // 1. Create virtual drive engine
        let engine = VirtualDriveEngine()
        engine.load(route: route, transportMode: transportMode)
        self.virtualDriveEngine = engine

        // 2. Remove map from RoutePreviewVC
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // 3. Configure map for navigation-like view
        let camera = MapCamera()
        camera.transportMode = transportMode
        let interpolator = MapInterpolator(mapCamera: camera)

        self.mapCamera = camera
        self.mapInterpolator = interpolator

        mapViewController.clearAll()
        mapViewController.configureForNavigation()
        mapViewController.showSingleRoute(route)

        // 4. Create a container VC for map + controls
        let containerVC = UIViewController()
        containerVC.view.backgroundColor = Theme.Colors.background

        // Add map as child
        containerVC.addChild(mapViewController)
        containerVC.view.addSubview(mapViewController.view)
        mapViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapViewController.view.topAnchor.constraint(equalTo: containerVC.view.topAnchor),
            mapViewController.view.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
            mapViewController.view.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
            mapViewController.view.bottomAnchor.constraint(equalTo: containerVC.view.bottomAnchor),
        ])
        mapViewController.didMove(toParent: containerVC)

        // 5. Start interpolation
        interpolator.start(mapViewController: mapViewController)

        // 6. Feed simulated locations into interpolator
        engine.simulatedLocationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                let heading = self?.virtualDriveEngine?.simulatedHeadingPublisher.value ?? 0
                self?.mapInterpolator?.updateTarget(
                    location: location,
                    heading: heading
                )
            }
            .store(in: &cancellables)

        // 7. Add back button
        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        backButton.tintColor = Theme.Colors.label
        backButton.backgroundColor = Theme.Colors.secondaryBackground
        backButton.layer.cornerRadius = 20
        backButton.layer.shadowColor = Theme.Shadow.color
        backButton.layer.shadowOpacity = Theme.Shadow.opacity
        backButton.layer.shadowOffset = Theme.Shadow.offset
        backButton.layer.shadowRadius = Theme.Shadow.radius
        containerVC.view.addSubview(backButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: containerVC.view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            backButton.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor, constant: Theme.Spacing.lg),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        backButton.addAction(UIAction { [weak self] _ in
            self?.stopVirtualDrive()
        }, for: .touchUpInside)

        // 8. Add virtual drive control overlay
        let controlView = VirtualDriveControlView()
        controlView.bind(to: engine)
        self.virtualDriveControlView = controlView
        containerVC.view.addSubview(controlView)

        NSLayoutConstraint.activate([
            controlView.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor, constant: 16),
            controlView.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor, constant: -16),
            controlView.bottomAnchor.constraint(equalTo: containerVC.view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        controlView.onPlayPause = { [weak engine] in
            guard let engine else { return }
            switch engine.playStatePublisher.value {
            case .playing:
                engine.pause()
            case .idle, .paused, .finished:
                engine.play()
            }
        }

        controlView.onStop = { [weak self] in
            self?.stopVirtualDrive()
        }

        controlView.onSpeedCycle = { [weak engine] in
            engine?.cycleSpeed()
        }

        // 9. Push container VC
        navigationController.pushViewController(containerVC, animated: true)

        // 10. Auto-play
        engine.play()
    }

    private func stopVirtualDrive() {
        virtualDriveEngine?.stop()
        virtualDriveEngine = nil

        virtualDriveControlView?.removeFromSuperview()
        virtualDriveControlView = nil

        // Stop interpolation
        mapInterpolator?.stop()
        mapInterpolator = nil
        mapCamera = nil

        // Remove map from container
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // Restore map to standard mode
        mapViewController.configureForStandard()
        mapViewController.clearAll()
        mapViewController.clearNavigationRoute()

        // Pop to home
        navigationController.popToViewController(homeViewController, animated: true)

        // Re-attach map to Home after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.returnMapToHome()
        }
    }

    // MARK: - GPX Playback Flow

    private var gpxSimulator: GPXSimulator?
    private var gpxPlaybackControlView: GPXPlaybackControlView?

    private func startGPXPlayback(record: GPXRecord) {
        let simulator = GPXSimulator()
        guard simulator.load(gpxFileURL: record.fileURL) else { return }
        self.gpxSimulator = simulator

        // Inject simulated locations into LocationService
        LocationService.shared.startLocationOverride(from: simulator.simulatedLocationPublisher)

        // Remove map from current parent
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // Configure map
        mapViewController.clearAll()
        mapViewController.configureForStandard()

        // Show the GPX track as a polyline overlay
        let parser = GPXParser()
        let locations = parser.parse(fileURL: record.fileURL)
        if locations.count >= 2 {
            let coordinates = locations.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapViewController.addOverlay(polyline)
        }

        // Create container VC
        let containerVC = UIViewController()
        containerVC.view.backgroundColor = Theme.Colors.background

        containerVC.addChild(mapViewController)
        containerVC.view.addSubview(mapViewController.view)
        mapViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapViewController.view.topAnchor.constraint(equalTo: containerVC.view.topAnchor),
            mapViewController.view.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
            mapViewController.view.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
            mapViewController.view.bottomAnchor.constraint(equalTo: containerVC.view.bottomAnchor),
        ])
        mapViewController.didMove(toParent: containerVC)

        // Back button
        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        backButton.tintColor = Theme.Colors.label
        backButton.backgroundColor = Theme.Colors.secondaryBackground
        backButton.layer.cornerRadius = 20
        backButton.layer.shadowColor = Theme.Shadow.color
        backButton.layer.shadowOpacity = Theme.Shadow.opacity
        backButton.layer.shadowOffset = Theme.Shadow.offset
        backButton.layer.shadowRadius = Theme.Shadow.radius
        containerVC.view.addSubview(backButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: containerVC.view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            backButton.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor, constant: Theme.Spacing.lg),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        backButton.addAction(UIAction { [weak self] _ in
            self?.stopGPXPlayback()
        }, for: .touchUpInside)

        // Playback control overlay
        let controlView = GPXPlaybackControlView()
        controlView.bind(to: simulator)
        self.gpxPlaybackControlView = controlView
        containerVC.view.addSubview(controlView)

        NSLayoutConstraint.activate([
            controlView.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor, constant: 16),
            controlView.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor, constant: -16),
            controlView.bottomAnchor.constraint(equalTo: containerVC.view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        controlView.onPlayPause = { [weak simulator] in
            guard let simulator else { return }
            if simulator.isPlayingPublisher.value {
                simulator.pause()
            } else {
                simulator.play()
            }
        }

        controlView.onStop = { [weak self] in
            self?.stopGPXPlayback()
        }

        controlView.onSpeedCycle = { [weak simulator] in
            guard let simulator else { return }
            let speeds: [Double] = [0.5, 1.0, 2.0, 4.0]
            let currentIdx = speeds.firstIndex(of: simulator.speedMultiplier) ?? 1
            simulator.speedMultiplier = speeds[(currentIdx + 1) % speeds.count]
        }

        navigationController.pushViewController(containerVC, animated: true)
        simulator.play()
    }

    private func stopGPXPlayback() {
        gpxSimulator?.stop()
        gpxSimulator = nil

        gpxPlaybackControlView?.removeFromSuperview()
        gpxPlaybackControlView = nil

        LocationService.shared.stopLocationOverride()

        // Remove map from container
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // Restore map
        mapViewController.configureForStandard()
        mapViewController.clearAll()

        // Pop to home
        navigationController.popToViewController(homeViewController, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.returnMapToHome()
        }
    }

    private func cleanUpNavigationUI() {
        // 1. Stop iPhone-only services
        mapInterpolator?.stop()
        turnPointPopupService?.reset()

        // 2. Remove map from NavigationVC
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // 3. Restore map to standard mode
        mapViewController.configureForStandard()
        mapViewController.clearAll()
        mapViewController.clearNavigationRoute()

        // 4. Pop to HomeVC
        navigationController.popToViewController(homeViewController, animated: true)

        // 5. Re-attach map to Home after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.returnMapToHome()
        }

        // 6. Clear iPhone-only references
        navigationViewController = nil
        mapInterpolator = nil
        mapCamera = nil
        turnPointPopupService = nil
    }
}
