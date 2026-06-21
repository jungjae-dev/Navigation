import UIKit
import Combine
import CoreLocation

/// 핀 기반 동네 인사이트 — MapItemContent 구현(기존 POI 팝업 재사용).
final class PinInsightContent: MapItemContent {

    /// 경로 버튼 → 해당 좌표로 길찾기 (Coordinator가 배선)
    var onRouteTapped: ((CLLocationCoordinate2D) -> Void)?
    /// 저장 → 관심 동네 (좌표, 동네명)
    var onSave: ((CLLocationCoordinate2D, String) -> Void)?
    /// 공유 → 요약 텍스트
    var onShare: ((String) -> Void)?

    private let coordinate: CLLocationCoordinate2D
    private let region: RegionCode
    private let viewModel: InsightViewModel
    private let view = PinInsightContentView()
    private var cancellables = Set<AnyCancellable>()

    init(coordinate: CLLocationCoordinate2D, region: RegionCode) {
        self.coordinate = coordinate
        self.region = region
        self.viewModel = InsightViewModel(coordinate: coordinate, region: region)
        bind()
        viewModel.load()
    }

    // MARK: - MapItemContent

    var iconImage: UIImage? {
        UIImage(systemName: "mappin.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.IconSize.lg, weight: .bold))
    }

    var title: String { region.displayAddress }
    var identifier: String { "insight:\(region.dongCode)" }
    var contentView: UIView { view }

    var footerActions: [MapItemAction] {
        [
            MapItemAction(title: "경로", iconName: "location.fill", style: .primary, handler: { [weak self] in
                guard let self else { return }
                self.onRouteTapped?(self.coordinate)
            }),
            MapItemAction(title: "저장", iconName: "star", style: .secondary, handler: { [weak self] in
                guard let self else { return }
                self.onSave?(self.coordinate, self.region.displayAddress)
            }),
            MapItemAction(title: "공유", iconName: "square.and.arrow.up", style: .secondary, handler: { [weak self] in
                guard let self else { return }
                self.onShare?(self.shareText())
            })
        ]
    }

    /// 현재 로드된 카드로 공유 텍스트 구성
    private func shareText() -> String {
        var lines = ["📍 \(region.displayAddress) 동네 인사이트"]
        for card in viewModel.cards.value {
            if case .loaded(let content) = card.state {
                lines.append("· \(card.kind.title): \(content.headline)")
            }
        }
        return lines.joined(separator: "\n")
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
