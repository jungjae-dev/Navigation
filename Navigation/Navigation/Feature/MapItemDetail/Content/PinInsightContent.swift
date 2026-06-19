import UIKit
import Combine
import CoreLocation

/// 핀 기반 동네 인사이트 — MapItemContent 구현(기존 POI 팝업 재사용).
final class PinInsightContent: MapItemContent {

    /// 경로 버튼 → 해당 좌표로 길찾기 (Coordinator가 배선; US2에서 RoutePreview 연결)
    var onRouteTapped: ((CLLocationCoordinate2D) -> Void)?

    private let coordinate: CLLocationCoordinate2D
    private let region: RegionCode
    private let viewModel: InsightViewModel
    private let view = PinInsightContentView()
    private var cancellables = Set<AnyCancellable>()

    init(coordinate: CLLocationCoordinate2D, region: RegionCode) {
        self.coordinate = coordinate
        self.region = region
        self.viewModel = InsightViewModel(region: region)
        bind()
        viewModel.load()
    }

    // MARK: - MapItemContent

    var iconImage: UIImage? {
        UIImage(systemName: "mappin.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))
    }

    var title: String { region.displayAddress }
    var identifier: String { "insight:\(region.dongCode)" }
    var contentView: UIView { view }

    var footerActions: [MapItemAction] {
        [
            MapItemAction(
                title: "경로",
                iconName: "location.fill",
                style: .primary,
                handler: { [weak self] in
                    guard let self else { return }
                    self.onRouteTapped?(self.coordinate)
                }
            )
        ]
    }

    // MARK: - Private

    private func bind() {
        viewModel.cards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cards in
                self?.view.configure(cards: cards)
            }
            .store(in: &cancellables)
    }
}
