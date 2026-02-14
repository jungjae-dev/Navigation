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

    // MARK: - Properties

    let destinationName: String?

    // MARK: - Private

    private let routeService: RouteService
    private let origin: CLLocationCoordinate2D
    private let destination: CLLocationCoordinate2D
    private let transportMode: TransportMode

    // MARK: - Init

    init(
        routeService: RouteService,
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationName: String?,
        transportMode: TransportMode = .automobile
    ) {
        self.routeService = routeService
        self.origin = origin
        self.destination = destination
        self.destinationName = destinationName
        self.transportMode = transportMode
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
}
