import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusViewModel")

@MainActor
final class BusViewModel {

    // MARK: - State

    private static let layerDefaultsKey = "layer.bus.enabled"

    let isLayerOnPublisher: CurrentValueSubject<Bool, Never>
    let busStopsPublisher = CurrentValueSubject<[BusStop], Never>([])

    var isLayerOn: Bool { isLayerOnPublisher.value }

    // MARK: - Dependencies

    private let dataService: TransitDataService
    private var cancellables = Set<AnyCancellable>()

    init(dataService: TransitDataService? = nil) {
        let saved = UserDefaults.standard.bool(forKey: Self.layerDefaultsKey)
        isLayerOnPublisher = CurrentValueSubject<Bool, Never>(saved)
        self.dataService = dataService ?? TransitDataService.shared
        bindDataService()
    }

    // MARK: - Actions

    func toggleLayer() {
        let newValue = !isLayerOn
        isLayerOnPublisher.send(newValue)
        UserDefaults.standard.set(newValue, forKey: Self.layerDefaultsKey)
        logger.info("Bus layer: \(newValue ? "ON" : "OFF")")
    }

    // MARK: - Private

    private func bindDataService() {
        dataService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .loaded(let busStops) = state {
                    self?.busStopsPublisher.send(busStops)
                }
            }
            .store(in: &cancellables)
    }
}
