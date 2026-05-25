import UIKit
import Combine
import CoreLocation

/// 따릉이 정류소 상세 컨텐츠 어댑터 — MapItemContent 프로토콜 구현
final class BikeStationContent: MapItemContent {

    var onWalkingRoute: ((BikeStation) -> Void)?
    var onRent: (() -> Void)?

    private(set) var station: BikeStation
    private let view = BikeStationContentView()
    private let cache: BikeStationCache
    private var distanceMeters: CLLocationDistance?
    private var lastUpdated: Date
    private var cancellables = Set<AnyCancellable>()

    init(station: BikeStation, cache: BikeStationCache = .shared) {
        self.station = station
        self.cache = cache
        self.lastUpdated = cache.lastUpdated.value ?? Date()
        view.configure(station: station)
        refreshInfo()
        subscribeCache()
    }

    // MARK: - Update

    func update(station: BikeStation) {
        self.station = station
        self.lastUpdated = cache.lastUpdated.value ?? Date()
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
        // 상류에서 자기 정류소만 추출 + 동일 데이터 중복 제거 → sink 호출 횟수 최소화
        let stationId = station.stationId
        cache.stations
            .compactMap { [weak cache] _ in cache?.station(id: stationId) }
            // == 는 stationId 기준이므로, 잔여 수 등 데이터 변경 감지를 위해 by: 명시
            .removeDuplicates(by: { $0.availableBikes == $1.availableBikes && $0.totalRacks == $1.totalRacks })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updated in
                guard let self else { return }
                self.station = updated
                self.lastUpdated = self.cache.lastUpdated.value ?? Date()
                self.view.configure(station: updated)
                self.refreshInfo()
            }
            .store(in: &cancellables)
    }
}
