import Foundation
import Combine
import CoreLocation

/// 동네 인사이트 카드 상태를 노출하는 ViewModel.
/// 상태는 CurrentValueSubject로 노출(@Published 미사용). 카드별 독립 갱신(FR-010).
final class InsightViewModel {

    let cards = CurrentValueSubject<[InsightCard], Never>([])

    private let coordinate: CLLocationCoordinate2D
    private let region: RegionCode
    private let service: NeighborhoodInsightService

    init(coordinate: CLLocationCoordinate2D,
         region: RegionCode,
         service: NeighborhoodInsightService = NeighborhoodInsightService()) {
        self.coordinate = coordinate
        self.region = region
        self.service = service
    }

    /// 카드 로드 시작 (슬라이스 2: 대기질 + 교통(따릉이) + 지금(행사))
    func load() {
        let kinds: [InsightCardKind] = [.airQuality, .transit, .greenery, .events]
        print("[Insight] 5. load cards (gu=\(region.guName), kinds=\(kinds.map { $0.rawValue }))")
        cards.send(kinds.map { InsightCard(kind: $0, state: .loading) })

        Task { [weak self] in
            guard let self else { return }
            self.apply(await self.service.airQualityCard(gu: self.region.guName))
        }
        Task { [weak self] in
            guard let self else { return }
            self.apply(await self.service.transitCard(at: self.coordinate))
        }
        Task { [weak self] in
            guard let self else { return }
            self.apply(await self.service.greeneryCard(at: self.coordinate))
        }
        Task { [weak self] in
            guard let self else { return }
            self.apply(await self.service.eventsCard(at: self.coordinate, gu: self.region.guName))
        }
    }

    /// 한 카드 결과를 배열에 반영 후 방출
    @MainActor
    private func apply(_ card: InsightCard) {
        var arr = cards.value
        if let i = arr.firstIndex(where: { $0.kind == card.kind }) {
            arr[i] = card
        } else {
            arr.append(card)
        }
        cards.send(arr)
        print("[Insight] 9. card \(card.kind.rawValue) updated → \(card.state)")
    }
}
