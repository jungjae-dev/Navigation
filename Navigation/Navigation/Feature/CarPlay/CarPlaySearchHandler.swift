import UIKit
import CarPlay
import MapKit
import Combine
import CoreLocation

final class CarPlaySearchHandler: NSObject {

    // MARK: - Callbacks

    var onRouteSelected: ((Route, Place) -> Void)?
    var onRoutePreview: ((Route) -> Void)?

    // MARK: - Dependencies

    weak var interfaceController: CPInterfaceController?
    weak var mapTemplate: CPMapTemplate?

    private let routeService: RouteProviding
    private let locationService: LocationService
    private let searchService: SearchProviding
    private let dataService: DataService

    // MARK: - State

    private var searchResults: [Place] = []
    private var selectedDestination: Place?
    var calculatedRoutes: [Route] = []

    // MARK: - Init

    init(routeService: RouteProviding, locationService: LocationService, searchService: SearchProviding, dataService: DataService = .shared) {
        self.routeService = routeService
        self.locationService = locationService
        self.searchService = searchService
        self.dataService = dataService
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
                // Show recent searches when empty
                let recents = self.dataService.fetchRecentSearches(limit: 8)
                let items = recents.map { history -> CPListItem in
                    let item = CPListItem(
                        text: history.placeName,
                        detailText: history.address,
                        image: UIImage(systemName: "clock.arrow.circlepath")
                    )
                    item.handler = { [weak self] _, completion in
                        let place = Place(
                            name: history.placeName,
                            coordinate: CLLocationCoordinate2D(latitude: history.latitude, longitude: history.longitude),
                            address: history.address,
                            phoneNumber: nil, url: nil, category: nil, providerRawData: nil
                        )
                        self?.handleResultSelected(place)
                        completion()
                    }
                    return item
                }
                completionHandler(items)
                return
            }

            Task { [weak self] in
                guard let self else {
                    completionHandler([])
                    return
                }

                do {
                    let results = try await self.searchService.search(query: searchText, region: nil)
                    self.searchResults = results

                    let items = results.prefix(12).map { place -> CPListItem in
                        let item = CPListItem(
                            text: place.name ?? "알 수 없는 장소",
                            detailText: place.address
                        )
                        item.handler = { [weak self] _, completion in
                            self?.handleResultSelected(place)
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

    func handleResultSelected(_ place: Place) {
        selectedDestination = place

        guard let userLocation = locationService.locationPublisher.value?.coordinate else {
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                let routes = try await self.routeService.calculateRoutes(
                    from: userLocation,
                    to: place.coordinate,
                    transportMode: .automobile
                )

                self.calculatedRoutes = routes

                guard let primaryRoute = routes.first else { return }

                // Show route preview on CarPlay map
                self.onRoutePreview?(primaryRoute)

                // Show trip previews on map template
                self.showTripPreviews(routes: routes, destination: place)

            } catch {
                print("[CarPlaySearch] Route calculation failed: \(error.localizedDescription)")
            }
        }
    }

    func showTripPreviews(routes: [Route], destination: Place) {
        guard let mapTemplate, let interfaceController else { return }

        // Pop search template
        interfaceController.popTemplate(animated: true, completion: nil)

        let origin = MKMapItem.forCurrentLocation()
        let destMapItem = destination.mkMapItem

        let routeChoices = routes.map { route -> CPRouteChoice in
            CPRouteChoice(
                summaryVariants: [route.formattedTravelTime + " · " + route.formattedDistance],
                additionalInformationVariants: [route.formattedArrivalTime],
                selectionSummaryVariants: [route.name]
            )
        }

        let trip = CPTrip(
            origin: origin,
            destination: destMapItem,
            routeChoices: routeChoices
        )

        // Show trip preview — user taps "Go" via CPMapTemplateDelegate
        mapTemplate.showTripPreviews([trip], textConfiguration: nil)
    }
}
