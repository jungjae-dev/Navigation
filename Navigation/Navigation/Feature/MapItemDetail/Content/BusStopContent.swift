import UIKit
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusStopContent")

/// 버스 정류소 상세 컨텐츠 어댑터 — MapItemContent 프로토콜 구현
final class BusStopContent: MapItemContent {

    // MARK: - Callbacks

    var onRouteTapped: ((BusArrival) -> Void)?
    var onTimetableTapped: (() -> Void)?
    var onWalkingRoute: ((BusStop) -> Void)?

    // MARK: - Properties

    private(set) var busStop: BusStop
    private let contentViewInstance = BusStopContentView()
    private let api: BusAPIClient
    private var isLoading = false

    // MARK: - Init

    init(busStop: BusStop, api: BusAPIClient = .shared) {
        self.busStop = busStop
        self.api = api
        setupCallbacks()
        Task { await fetchArrivals() }
    }

    // MARK: - MapItemContent

    var iconImage: UIImage? {
        UIImage(systemName: "bus.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.IconSize.lg, weight: .medium))
    }

    var title: String { busStop.name }
    var identifier: String { "bus:\(busStop.stId)" }
    var contentView: UIView { contentViewInstance }

    var footerActions: [MapItemAction] {
        [
            MapItemAction(
                title: "시간표",
                iconName: "clock",
                style: .secondary,
                handler: { [weak self] in self?.onTimetableTapped?() }
            ),
            MapItemAction(
                title: "도보 길찾기",
                iconName: "figure.walk",
                style: .secondary,
                handler: { [weak self] in
                    guard let self else { return }
                    self.onWalkingRoute?(self.busStop)
                }
            )
        ]
    }

    // MARK: - Private

    private func setupCallbacks() {
        contentViewInstance.onRouteTapped = { [weak self] arrival in
            self?.onRouteTapped?(arrival)
        }
        contentViewInstance.onRefreshTapped = { [weak self] in
            Task { await self?.fetchArrivals() }
        }
    }

    private func fetchArrivals() async {
        guard !isLoading else { return }
        isLoading = true
        logger.info("[BusStopContent] fetchArrivals start — stId=\(self.busStop.stId) arsId=\(self.busStop.arsId) name=\(self.busStop.name)")
        contentViewInstance.showLoading()
        contentViewInstance.setRefreshing(true)

        do {
            let arrivals = try await api.fetchArrivals(arsId: busStop.arsId)
            logger.info("[BusStopContent] arrivals loaded: \(arrivals.count) routes — arsId=\(self.busStop.arsId)")
            await MainActor.run {
                contentViewInstance.configure(arrivals: arrivals)
                contentViewInstance.setRefreshing(false)
            }
        } catch {
            logger.error("[BusStopContent] fetchArrivals failed: \(error.localizedDescription) — arsId=\(self.busStop.arsId)")
            await MainActor.run {
                contentViewInstance.configure(arrivals: [])
                contentViewInstance.setRefreshing(false)
            }
        }
        isLoading = false
    }
}
