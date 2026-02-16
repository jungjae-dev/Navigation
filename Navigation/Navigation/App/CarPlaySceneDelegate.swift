import UIKit
import CarPlay
import Combine

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var carPlayWindow: CPWindow?
    private var carPlayMapVC: CarPlayMapViewController?
    private var mapTemplate: CPMapTemplate?

    private var searchHandler: CarPlaySearchHandler?
    private var navigationHandler: CarPlayNavigationHandler?

    private let sessionManager = NavigationSessionManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CPTemplateApplicationSceneDelegate

    nonisolated func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        MainActor.assumeIsolated {
            self.interfaceController = interfaceController
            self.carPlayWindow = window

            setupCarPlayMap(in: window)
            setupMapTemplate(with: interfaceController)
            setupSearchHandler()
            setupNavigationHandler()
            observeNavigationSession()
        }
    }

    nonisolated func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        MainActor.assumeIsolated {
            tearDown()
        }
    }

    // MARK: - Setup

    private func setupCarPlayMap(in window: CPWindow) {
        let mapVC = CarPlayMapViewController(
            locationService: LocationService.shared,
            sessionManager: sessionManager
        )
        window.rootViewController = mapVC
        carPlayMapVC = mapVC
    }

    private func setupMapTemplate(with controller: CPInterfaceController) {
        let template = CPMapTemplate()
        template.mapDelegate = self

        // Search button
        let searchButton = CPBarButton(title: "검색") { [weak self] _ in
            self?.showSearch()
        }
        template.leadingNavigationBarButtons = [searchButton]

        self.mapTemplate = template
        controller.setRootTemplate(template, animated: false, completion: nil)
    }

    private func setupSearchHandler() {
        let handler = CarPlaySearchHandler(
            routeService: RouteService(),
            locationService: LocationService.shared
        )

        handler.onRouteSelected = { [weak self] route, destination in
            self?.startNavigationFromCarPlay(route: route, destination: destination)
        }

        handler.onRoutePreview = { [weak self] route in
            self?.carPlayMapVC?.showRoute(route)
        }

        self.searchHandler = handler
    }

    private func setupNavigationHandler() {
        self.navigationHandler = CarPlayNavigationHandler()
    }

    // MARK: - Navigation Session Observation

    private func observeNavigationSession() {
        sessionManager.navigationCommandPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] command in
                switch command {
                case .started(let source):
                    if source == .phone {
                        // Navigation started from iPhone → reflect on CarPlay
                        self?.handlePhoneNavigationStarted()
                    }
                case .stopped:
                    self?.handleNavigationStopped()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Search

    private func showSearch() {
        guard let searchHandler, let interfaceController else { return }

        let searchTemplate = CPSearchTemplate()
        searchTemplate.delegate = searchHandler
        searchHandler.interfaceController = interfaceController
        searchHandler.mapTemplate = mapTemplate

        interfaceController.pushTemplate(searchTemplate, animated: true, completion: nil)
    }

    // MARK: - Navigation

    private func startNavigationFromCarPlay(route: MKRoute, destination: MKMapItem) {
        sessionManager.startNavigation(
            route: route,
            destination: destination,
            source: .carPlay
        )

        guard let session = sessionManager.activeSessionPublisher.value,
              let mapTemplate else { return }

        // Create CPTrip for the navigation session
        let origin = MKMapItem.forCurrentLocation()
        let routeChoice = CPRouteChoice(
            summaryVariants: [route.formattedTravelTime + " · " + route.formattedDistance],
            additionalInformationVariants: [route.formattedArrivalTime],
            selectionSummaryVariants: [route.name]
        )
        let trip = CPTrip(origin: origin, destination: destination, routeChoices: [routeChoice])

        navigationHandler?.startNavigation(
            trip: trip,
            mapTemplate: mapTemplate,
            guidanceEngine: session.guidanceEngine
        )
    }

    private func handlePhoneNavigationStarted() {
        guard let session = sessionManager.activeSessionPublisher.value,
              let mapTemplate else { return }

        // Pop any search templates
        if let interfaceController {
            interfaceController.popToRootTemplate(animated: false, completion: nil)
        }

        // Create CPTrip from session data
        let origin = MKMapItem.forCurrentLocation()
        let routeChoice = CPRouteChoice(
            summaryVariants: [session.route.formattedTravelTime + " · " + session.route.formattedDistance],
            additionalInformationVariants: [session.route.formattedArrivalTime],
            selectionSummaryVariants: [session.route.name]
        )
        let trip = CPTrip(origin: origin, destination: session.destination, routeChoices: [routeChoice])

        navigationHandler?.startNavigation(
            trip: trip,
            mapTemplate: mapTemplate,
            guidanceEngine: session.guidanceEngine
        )
    }

    private func handleNavigationStopped() {
        navigationHandler?.stopNavigation()
        carPlayMapVC?.clearRoute()
    }

    // MARK: - Teardown

    private func tearDown() {
        navigationHandler?.stopNavigation()
        cancellables.removeAll()
        carPlayMapVC = nil
        searchHandler = nil
        navigationHandler = nil
        mapTemplate = nil
        interfaceController = nil
        carPlayWindow = nil
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlaySceneDelegate: CPMapTemplateDelegate {

    nonisolated func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        startedTrip trip: CPTrip,
        using routeChoice: CPRouteChoice
    ) {
        MainActor.assumeIsolated {
            guard let searchHandler else { return }

            // Use first calculated route (or match by routeChoice if multiple)
            let selectedRoute = searchHandler.calculatedRoutes.first
                ?? searchHandler.calculatedRoutes[0]

            let destination = trip.destination
            startNavigationFromCarPlay(route: selectedRoute, destination: destination)
            mapTemplate.hideTripPreviews()
        }
    }
}
