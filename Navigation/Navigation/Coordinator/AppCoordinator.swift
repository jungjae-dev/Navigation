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

    private var mapViewController: MapViewController!
    private var homeViewController: HomeViewController!
    private var currentDrawer: SearchResultDrawerViewController?

    // MARK: - Sprint 3: Navigation Services

    private var navigationViewController: NavigationViewController?
    private var guidanceEngine: GuidanceEngine?
    private var voiceService: VoiceGuidanceService?
    private var offRouteDetector: OffRouteDetector?
    private var mapInterpolator: MapInterpolator?
    private var mapCamera: MapCamera?
    private var turnPointPopupService: TurnPointPopupService?

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

        navigationController.setViewControllers([homeVC], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
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

        routePreviewVC.onStartNavigation = { [weak self] route in
            self?.startNavigation(with: route)
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

    // MARK: - Navigation Flow (Sprint 3)

    private func startNavigation(with route: MKRoute) {
        // 1. Configure location service for navigation
        locationService.configureForNavigation()

        // 2. Create all navigation services
        let voice = VoiceGuidanceService()
        let offRoute = OffRouteDetector()
        let camera = MapCamera()

        let engine = GuidanceEngine(
            locationService: locationService,
            routeService: routeService,
            voiceService: voice,
            offRouteDetector: offRoute
        )

        let interpolator = MapInterpolator(mapCamera: camera)
        let popup = TurnPointPopupService(
            guidanceEngine: engine,
            locationService: locationService
        )

        // Store references
        self.voiceService = voice
        self.offRouteDetector = offRoute
        self.guidanceEngine = engine
        self.mapCamera = camera
        self.mapInterpolator = interpolator
        self.turnPointPopupService = popup

        // 3. Remove map from RoutePreviewVC
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // 4. Configure map for navigation mode
        mapViewController.clearAll()
        mapViewController.configureForNavigation()
        mapViewController.showSingleRoute(route)

        // 5. Create NavigationViewModel
        let navViewModel = NavigationViewModel(
            guidanceEngine: engine,
            mapInterpolator: interpolator,
            turnPointPopupService: popup,
            locationService: locationService,
            mapCamera: camera
        )

        // 6. Create NavigationViewController
        let navVC = NavigationViewController(
            viewModel: navViewModel,
            mapViewController: mapViewController,
            turnPointPopupService: popup
        )
        self.navigationViewController = navVC

        navVC.onDismiss = { [weak self] in
            self?.dismissNavigation()
        }

        // 7. Start all services
        interpolator.start(mapViewController: mapViewController)
        navViewModel.startNavigation(with: route)

        // 8. Push NavigationVC (replaces RoutePreviewVC)
        navigationController.pushViewController(navVC, animated: true)
    }

    private func dismissNavigation() {
        // 1. Stop all services
        guidanceEngine?.stopNavigation()
        mapInterpolator?.stop()
        voiceService?.stop()
        offRouteDetector?.reset()
        turnPointPopupService?.reset()

        // 2. Restore location service to standard mode
        locationService.configureForStandard()

        // 3. Remove map from NavigationVC
        mapViewController.willMove(toParent: nil)
        mapViewController.view.removeFromSuperview()
        mapViewController.removeFromParent()

        // 4. Restore map to standard mode
        mapViewController.configureForStandard()
        mapViewController.clearAll()
        mapViewController.clearNavigationRoute()

        // 5. Pop to HomeVC
        navigationController.popToViewController(homeViewController, animated: true)

        // 6. Re-attach map to Home after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.returnMapToHome()
        }

        // 7. Clear references
        navigationViewController = nil
        guidanceEngine = nil
        voiceService = nil
        offRouteDetector = nil
        mapInterpolator = nil
        mapCamera = nil
        turnPointPopupService = nil
    }
}
