import Foundation
import CoreLocation

/// 좌표 → 행정구역 식별 결과 (Kakao coord2regioncode).
/// 코드는 문자열로 보관(앞자리 0 보존).
struct RegionCode: Sendable, Equatable {
    let guName: String      // 자치구명 (예: "마포구")
    let dongName: String    // 행정동명 (예: "서교동")
    let guCode: String      // 자치구 코드
    let dongCode: String    // 행정동 코드

    /// 헤더 표시용 주소 (예: "마포구 서교동")
    var displayAddress: String {
        [guName, dongName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// 한 핀 좌표에 대한 동네 인사이트 종합 결과 (메모리 모델, 비영속)
struct NeighborhoodInsight: Sendable {
    let coordinate: CLLocationCoordinate2D
    let region: RegionCode
    /// 한 줄 요약 (규칙 기반 생성, 예: "조용하고 공기 좋은 주거 동네")
    var summary: String
    /// 카드 묶음 (InsightCardKind 순서 고정)
    var cards: [InsightCard]

    init(coordinate: CLLocationCoordinate2D,
         region: RegionCode,
         summary: String = "",
         cards: [InsightCard] = InsightCardKind.allCases.map { InsightCard(kind: $0) }) {
        self.coordinate = coordinate
        self.region = region
        self.summary = summary
        self.cards = cards
    }
}

extension NeighborhoodInsight {
    /// 특정 종류 카드를 갱신
    mutating func update(_ kind: InsightCardKind, state: CardState, asOf: Date? = nil) {
        guard let idx = cards.firstIndex(where: { $0.kind == kind }) else { return }
        cards[idx].state = state
        if let asOf { cards[idx].asOf = asOf }
    }
}
