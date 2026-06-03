import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusViewModel")

@MainActor
final class BusViewModel {

    // MARK: - State

    let isLayerOnPublisher = CurrentValueSubject<Bool, Never>(false)
    let busStopsPublisher = CurrentValueSubject<[BusStop], Never>([])

    var isLayerOn: Bool { isLayerOnPublisher.value }

    // MARK: - Dependencies

    private let dataService: TransitDataService
    private var cancellables = Set<AnyCancellable>()

    init(dataService: TransitDataService? = nil) {
        self.dataService = dataService ?? TransitDataService.shared
        bindDataService()
    }

    // MARK: - Actions

    func toggleLayer() {
        isLayerOnPublisher.send(!isLayerOn)
        logger.info("Bus layer: \(self.isLayerOn ? "ON" : "OFF")")
    }

    // MARK: - Private

    private func bindDataService() {
        dataService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .loaded(let busStops, _, _) = state {
                    self?.busStopsPublisher.send(busStops)
                }
            }
            .store(in: &cancellables)
    }
}
