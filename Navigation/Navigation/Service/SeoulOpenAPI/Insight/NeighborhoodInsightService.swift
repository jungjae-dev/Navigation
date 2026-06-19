import Foundation

/// 동네 인사이트 카드별 데이터 집계.
/// (슬라이스 1: 대기질 카드만 구현 — 이후 슬라이스에서 카드 추가)
final class NeighborhoodInsightService {

    private let airQuality = AirQualityService()

    /// 대기질 카드 1장 로드 (실패해도 throw 안 함 — 카드 상태로 격리, FR-010)
    func airQualityCard(gu: String) async -> InsightCard {
        do {
            let content = try await airQuality.airQuality(gu: gu)
            print("[Insight] card airQuality → loaded: \(content.headline)")
            return InsightCard(kind: .airQuality, state: .loaded(content), asOf: Date())
        } catch {
            print("[Insight] card airQuality → FAILED: \(error)")
            return InsightCard(kind: .airQuality, state: .failed)
        }
    }
}
