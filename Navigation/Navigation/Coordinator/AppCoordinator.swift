import UIKit

final class AppCoordinator: Coordinator {

    // MARK: - Coordinator

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []

    // MARK: - Properties

    private let window: UIWindow
    private let locationService: LocationService

    // MARK: - Init

    init(window: UIWindow) {
        self.window = window
        self.locationService = .shared
        self.navigationController = UINavigationController()
        self.navigationController.isNavigationBarHidden = true
    }

    // MARK: - Start

    func start() {
        let mapViewController = MapViewController(locationService: locationService)
        let homeViewModel = HomeViewModel(locationService: locationService)
        let homeViewController = HomeViewController(
            viewModel: homeViewModel,
            mapViewController: mapViewController
        )

        navigationController.setViewControllers([homeViewController], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }
}
