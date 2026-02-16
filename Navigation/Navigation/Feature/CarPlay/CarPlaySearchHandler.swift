import UIKit
import CarPlay
import MapKit
import Combine
import CoreLocation

final class CarPlaySearchHandler: NSObject {

    // MARK: - Callbacks

    var onRouteSelected: ((MKRoute, MKMapItem) -> Void)?
    var onRoutePreview: ((MKRoute) -> Void)?

    // MARK: - Dependencies

    weak var interfaceController: CPInterfaceController?
    weak var mapTemplate: CPMapTemplate?

    private let routeService: RouteService
    private let locationService: LocationService
    private let searchService: SearchService

    // MARK: - State

    private var searchResults: [MKMapItem] = []
    private var selectedDestination: MKMapItem?
    private(set) var calculatedRoutes: [MKRoute] = []

    // MARK: - Init

    init(routeService: RouteService, locationService: LocationService) {
        self.routeService = routeService
        self.locationService = locationService
        self.searchService = SearchService()
        super.init()
    }
}

// MARK: - CPSearchTemplateDelegate

extension CarPlaySearchHandler: CPSearchTemplateDelegate {

    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        MainActor.assumeIsolated {
            guard !searchText.isEmpty else {
                completionHandler([])
                return
            }

            Task { [weak self] in
                guard let self else {
                    completionHandler([])
                    return
                }

                do {
                    let results = try await self.searchService.search(query: searchText)
                    self.searchResults = results

                    let items = results.prefix(12).map { mapItem -> CPListItem in
                        let addressText = mapItem.address?.fullAddress
                        let item = CPListItem(
                            text: mapItem.name ?? "알 수 없는 장소",
                            detailText: addressText
                        )
                        item.handler = { [weak self] _, completion in
                            self?.handleResultSelected(mapItem)
                            completion()
                        }
                        return item
                    }

                    completionHandler(items)
                } catch {
                    completionHandler([])
                }
            }
        }
    }

    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated {
            completionHandler()
        }
    }
}

// MARK: - Route Handling

extension CarPlaySearchHandler {

    func handleResultSelected(_ mapItem: MKMapItem) {
        selectedDestination = mapItem

        guard let userLocation = locationService.locationPublisher.value?.coordinate else {
            return
        }

        let destination = mapItem.location.coordinate

        Task { [weak self] in
            guard let self else { return }

            do {
                let routes = try await self.routeService.calculateRoutes(
                    from: userLocation,
                    to: destination
                )

                self.calculatedRoutes = routes

                guard let primaryRoute = routes.first else { return }

                // Show route preview on CarPlay map
                self.onRoutePreview?(primaryRoute)

                // Show trip previews on map template
                self.showTripPreviews(routes: routes, destination: mapItem)

            } catch {
                print("[CarPlaySearch] Route calculation failed: \(error.localizedDescription)")
            }
        }
    }

    func showTripPreviews(routes: [MKRoute], destination: MKMapItem) {
        guard let mapTemplate, let interfaceController else { return }

        // Pop search template
        interfaceController.popTemplate(animated: true, completion: nil)

        let origin = MKMapItem.forCurrentLocation()

        let routeChoices = routes.map { route -> CPRouteChoice in
            CPRouteChoice(
                summaryVariants: [route.formattedTravelTime + " \u{00B7} " + route.formattedDistance],
                additionalInformationVariants: [route.formattedArrivalTime],
                selectionSummaryVariants: [route.name]
            )
        }

        let trip = CPTrip(
            origin: origin,
            destination: destination,
            routeChoices: routeChoices
        )

        // Show trip preview — user taps "Go" via CPMapTemplateDelegate
        mapTemplate.showTripPreviews([trip], textConfiguration: nil)
    }
}
