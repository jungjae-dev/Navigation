import Foundation
import Combine

/// 동네 인사이트 카드 상태를 노출하는 ViewModel.
/// 상태는 CurrentValueSubject로 노출(@Published 미사용).
final class InsightViewModel {

    /// 표시할 카드 목록(상태 포함). 카드별 독립 갱신.
    let cards = CurrentValueSubject<[InsightCard], Never>([])

    private let region: RegionCode
    private let service: NeighborhoodInsightService

    init(region: RegionCode, service: NeighborhoodInsightService = NeighborhoodInsightService()) {
        self.region = region
        self.service = service
    }

    /// 카드 로드 시작 (슬라이스 1: 대기질만)
    func load() {
        print("[Insight] 5. load cards (gu=\(region.guName))")
        cards.send([InsightCard(kind: .airQuality, state: .loading)])
        Task { @MainActor in
            let card = await service.airQualityCard(gu: region.guName)
            cards.send([card])
            print("[Insight] 9. cards updated (\(cards.value.count)) → airQuality state=\(card.state)")
        }
    }
}
