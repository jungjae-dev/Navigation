import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "SubwayViewModel")

@MainActor
final class SubwayViewModel {

    // MARK: - State

    let isLayerOnPublisher = CurrentValueSubject<Bool, Never>(false)
    let subwayStationsPublisher = CurrentValueSubject<[SubwayStation], Never>([])
    let subwayLinesPublisher = CurrentValueSubject<SubwayLines, Never>([:])

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
        logger.info("Subway layer: \(self.isLayerOn ? "ON" : "OFF")")
    }

    // MARK: - Private

    private func bindDataService() {
        dataService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .loaded(_, let stations, let lines) = state {
                    self?.subwayStationsPublisher.send(stations)
                    self?.subwayLinesPublisher.send(lines)
                }
            }
            .store(in: &cancellables)
    }
}
