import UIKit
import CoreLocation

/// POI(Place) 상세 컨텐츠 어댑터 — MapItemContent 프로토콜 구현
final class PlaceContent: MapItemContent {

    var onRouteTapped: ((Place) -> Void)?

    private(set) var place: Place
    private let dataService: DataService
    private let view = PlaceContentView()

    init(place: Place, dataService: DataService = .shared) {
        self.place = place
        self.dataService = dataService
        view.onFavoriteToggled = { [weak self] in self?.toggleFavorite() }
        refreshContentView()
    }

    // MARK: - Update

    func update(place: Place) {
        self.place = place
        refreshContentView()
    }

    private func refreshContentView() {
        let isFav = dataService.isFavorite(
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude
        )
        view.configure(with: place, isFavorite: isFav)
    }

    private func toggleFavorite() {
        let coord = place.coordinate
        if dataService.isFavorite(latitude: coord.latitude, longitude: coord.longitude) {
            if let existing = dataService.findFavorite(latitude: coord.latitude, longitude: coord.longitude) {
                dataService.deleteFavorite(existing)
            }
        } else {
            let name = place.name ?? "즐겨찾기"
            let address = place.address ?? ""
            dataService.saveFavoriteFromCoordinate(
                name: name,
                address: address,
                latitude: coord.latitude,
                longitude: coord.longitude
            )
        }
        refreshContentView()
    }

    // MARK: - MapItemContent

    var iconImage: UIImage? {
        let name = POICategoryIcon.iconName(for: place.category)
        return UIImage(systemName: name)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.IconSize.lg, weight: .medium))
    }

    var title: String { place.name ?? "알 수 없는 장소" }

    var identifier: String {
        "place:\(place.coordinate.latitude),\(place.coordinate.longitude)"
    }

    var contentView: UIView { view }

    var footerActions: [MapItemAction] {
        [
            MapItemAction(
                title: "경로",
                iconName: "arrow.triangle.turn.up.right.diamond.fill",
                style: .primary,
                handler: { [weak self] in
                    guard let self else { return }
                    self.onRouteTapped?(self.place)
                }
            )
        ]
    }
}
