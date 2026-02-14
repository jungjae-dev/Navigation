import Foundation
import Combine
import MapKit
import CoreLocation

final class RoutePreviewViewModel {

    // MARK: - Publishers

    let routes = CurrentValueSubject<[MKRoute], Never>([])
    let selectedRouteIndex = CurrentValueSubject<Int, Never>(0)
    let isCalculating = CurrentValueSubject<Bool, Never>(false)
    let errorMessage = CurrentValueSubject<String?, Never>(nil)
    let isFavorite = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Properties

    let destinationName: String?
    let destinationAddress: String?

    // MARK: - Private

    private let routeService: RouteService
    private let dataService: DataService
    private let origin: CLLocationCoordinate2D
    private let destination: CLLocationCoordinate2D
    private let transportMode: TransportMode

    // MARK: - Init

    init(
        routeService: RouteService,
        dataService: DataService = .shared,
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationName: String?,
        destinationAddress: String? = nil,
        transportMode: TransportMode = .automobile
    ) {
        self.routeService = routeService
        self.dataService = dataService
        self.origin = origin
        self.destination = destination
        self.destinationName = destinationName
        self.destinationAddress = destinationAddress
        self.transportMode = transportMode

        // Check initial favorite state
        isFavorite.send(
            dataService.isFavorite(latitude: destination.latitude, longitude: destination.longitude)
        )
    }

    // MARK: - Actions

    func calculateRoutes() async {
        isCalculating.send(true)
        errorMessage.send(nil)

        do {
            let calculatedRoutes = try await routeService.calculateRoutes(
                from: origin,
                to: destination,
                transportType: transportMode.mkTransportType
            )
            routes.send(calculatedRoutes)
        } catch {
            errorMessage.send(error.localizedDescription)
        }

        isCalculating.send(false)
    }

    func selectRoute(at index: Int) {
        guard index < routes.value.count else { return }
        selectedRouteIndex.send(index)
    }

    func getSelectedRoute() -> MKRoute? {
        let index = selectedRouteIndex.value
        guard index < routes.value.count else { return nil }
        return routes.value[index]
    }

    // MARK: - Favorite

    func toggleFavorite() {
        if isFavorite.value {
            // Remove favorite
            if let existing = dataService.findFavorite(latitude: destination.latitude, longitude: destination.longitude) {
                dataService.deleteFavorite(existing)
            }
            isFavorite.send(false)
        } else {
            // Add favorite
            let name = destinationName ?? "즐겨찾기"
            let address = destinationAddress ?? ""
            dataService.saveFavoriteFromCoordinate(
                name: name,
                address: address,
                latitude: destination.latitude,
                longitude: destination.longitude
            )
            isFavorite.send(true)
        }
    }
}
