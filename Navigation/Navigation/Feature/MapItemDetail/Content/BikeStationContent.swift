import UIKit
import Combine
import CoreLocation

/// 따릉이 정류소 상세 컨텐츠 어댑터 — MapItemContent 프로토콜 구현
final class BikeStationContent: MapItemContent {

    var onWalkingRoute: ((BikeStation) -> Void)?
    var onRent: (() -> Void)?

    private(set) var station: BikeStation
    private let view = BikeStationContentView()
    private var distanceMeters: CLLocationDistance?
    private var lastUpdated: Date
    private var cancellables = Set<AnyCancellable>()

    init(station: BikeStation) {
        self.station = station
        self.lastUpdated = BikeStationCache.shared.lastUpdated.value ?? Date()
        view.configure(station: station)
        refreshInfo()
        subscribeCache()
    }

    // MARK: - Update

    func update(station: BikeStation) {
        self.station = station
        self.lastUpdated = BikeStationCache.shared.lastUpdated.value ?? Date()
        view.configure(station: station)
        refreshInfo()
    }

    // MARK: - MapItemContent

    var iconImage: UIImage? {
        UIImage(systemName: "bicycle")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.IconSize.lg - 4, weight: .bold))
    }

    var title: String { station.stationName }
    var identifier: String { "bike:\(station.stationId)" }
    var contentView: UIView { view }

    var footerActions: [MapItemAction] {
        [
            MapItemAction(
                title: "도보 길찾기",
                iconName: "figure.walk",
                style: .secondary,
                handler: { [weak self] in
                    guard let self else { return }
                    self.onWalkingRoute?(self.station)
                }
            ),
            MapItemAction(
                title: "대여하기",
                iconName: "bicycle.circle.fill",
                style: .primary,
                handler: { [weak self] in self?.onRent?() }
            )
        ]
    }

    func updateDistance(from coordinate: CLLocationCoordinate2D?) {
        guard let from = coordinate else {
            distanceMeters = nil
            refreshInfo()
            return
        }
        let a = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let b = CLLocation(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)
        distanceMeters = a.distance(from: b)
        refreshInfo()
    }

    // MARK: - Private

    private func refreshInfo() {
        var parts: [String] = []
        if let m = distanceMeters {
            parts.append(m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000))
        }
        let elapsed = max(0, Int(Date().timeIntervalSince(lastUpdated) / 60))
        parts.append(elapsed < 1 ? "방금 전 갱신" : "\(elapsed)분 전 갱신")
        view.setInfoText(parts.joined(separator: " · "))
    }

    private func subscribeCache() {
        BikeStationCache.shared.stations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self,
                      let updated = BikeStationCache.shared.station(id: self.station.stationId)
                else { return }
                self.station = updated
                self.lastUpdated = BikeStationCache.shared.lastUpdated.value ?? Date()
                self.view.configure(station: updated)
                self.refreshInfo()
            }
            .store(in: &cancellables)
    }
}
