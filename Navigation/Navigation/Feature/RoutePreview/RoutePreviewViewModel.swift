import Foundation
import Combine
import CoreLocation

final class RoutePreviewViewModel {

    // MARK: - Publishers

    let routes = CurrentValueSubject<[Route], Never>([])
    let selectedRouteIndex = CurrentValueSubject<Int, Never>(0)
    let isCalculating = CurrentValueSubject<Bool, Never>(false)
    let errorMessage = CurrentValueSubject<String?, Never>(nil)
    let transportModePublisher = CurrentValueSubject<TransportMode, Never>(.automobile)

    // MARK: - Properties

    let destinationName: String?
    let destinationAddress: String?

    // MARK: - Private

    private let routeService: RouteProviding
    private let origin: CLLocationCoordinate2D
    private let destination: CLLocationCoordinate2D

    // MARK: - Init

    init(
        routeService: RouteProviding,
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationName: String?,
        destinationAddress: String? = nil,
        transportMode: TransportMode = .automobile
    ) {
        self.routeService = routeService
        self.origin = origin
        self.destination = destination
        self.destinationName = destinationName
        self.destinationAddress = destinationAddress
        self.transportModePublisher.send(transportMode)
    }

    // MARK: - Transport Mode

    var transportMode: TransportMode {
        transportModePublisher.value
    }

    func setTransportMode(_ mode: TransportMode) {
        transportModePublisher.send(mode)
        routes.send([])
        selectedRouteIndex.send(0)
    }

    // MARK: - Actions

    func calculateRoutes() async {
        isCalculating.send(true)
        errorMessage.send(nil)

        do {
            let calculatedRoutes = try await routeService.calculateRoutes(
                from: origin,
                to: destination,
                transportMode: transportModePublisher.value
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

    func getSelectedRoute() -> Route? {
        let index = selectedRouteIndex.value
        guard index < routes.value.count else { return nil }
        return routes.value[index]
    }

}
