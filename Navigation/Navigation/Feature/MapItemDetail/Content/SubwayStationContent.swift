import UIKit
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "SubwayStationContent")

/// 지하철역 상세 컨텐츠 어댑터 — MapItemContent 프로토콜 구현
final class SubwayStationContent: MapItemContent {

    // MARK: - Callbacks

    var onLineTapped: ((String) -> Void)?
    var onTimetableTapped: (() -> Void)?
    var onWalkingRoute: ((SubwayStation) -> Void)?

    // MARK: - Properties

    private(set) var station: SubwayStation
    private let lines: SubwayLines
    private let contentViewInstance: SubwayStationContentView
    private let api: SubwayAPIClient
    private var isLoading = false

    // MARK: - Init

    init(station: SubwayStation, lines: SubwayLines, api: SubwayAPIClient = .shared) {
        self.station = station
        self.lines = lines
        self.contentViewInstance = SubwayStationContentView()
        self.api = api
        setupCallbacks()
        Task { await fetchArrivals() }
    }

    // MARK: - MapItemContent

    var iconImage: UIImage? {
        UIImage(systemName: "tram.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.IconSize.lg, weight: .medium))
    }

    var title: String { station.name }
    var identifier: String { "subway:\(station.stationCode)" }
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
                    self.onWalkingRoute?(self.station)
                }
            )
        ]
    }

    // MARK: - Private

    private func setupCallbacks() {
        contentViewInstance.onLineTapped = { [weak self] lineName in
            self?.onLineTapped?(lineName)
        }
        contentViewInstance.onRefreshTapped = { [weak self] in
            Task { await self?.fetchArrivals() }
        }
    }

    private func fetchArrivals() async {
        guard !isLoading else { return }
        isLoading = true
        contentViewInstance.showLoading()
        contentViewInstance.setRefreshing(true)

        do {
            let arrivals = try await api.fetchArrivals(stationName: station.name)
            await MainActor.run {
                contentViewInstance.configure(arrivals: arrivals, lines: lines)
                contentViewInstance.setRefreshing(false)
            }
        } catch {
            logger.error("Subway API error: \(error.localizedDescription)")
            await MainActor.run {
                contentViewInstance.configure(arrivals: [], lines: lines)
                contentViewInstance.setRefreshing(false)
            }
        }
        isLoading = false
    }
}
