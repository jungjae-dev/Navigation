import Foundation

/// 동네 인사이트 카드 종류 (표시 순서 = case 순서)
enum InsightCardKind: String, CaseIterable, Sendable {
    case vitality       // 생활 활기
    case airQuality     // 대기질
    case transit        // 교통
    case amenity        // 편의
    case greenery       // 녹지·산책
    case safety         // 안전
    case events         // 지금(주변 행사)

    /// 헤더용 SF Symbol
    var symbolName: String {
        switch self {
        case .vitality:   return "figure.walk.motion"
        case .airQuality: return "aqi.medium"
        case .transit:    return "tram.fill"
        case .amenity:    return "cross.case.fill"
        case .greenery:   return "tree.fill"
        case .safety:     return "shield.lefthalf.filled"
        case .events:     return "sparkles"
        }
    }

    var title: String {
        switch self {
        case .vitality:   return "생활 활기"
        case .airQuality: return "대기질"
        case .transit:    return "교통"
        case .amenity:    return "생활 편의"
        case .greenery:   return "녹지·산책"
        case .safety:     return "안전"
        case .events:     return "지금 주변"
        }
    }

    /// 실시간 값이라 기준 시각('○분 전')을 표시해야 하는 카드인지
    var isRealtime: Bool {
        switch self {
        case .airQuality, .transit: return true
        default: return false
        }
    }
}

/// 카드 핵심 값 옆에 붙는 강조 배지 색상 단계 (Theme.Palette 경유로 렌더)
enum CardBadgeLevel: Sendable {
    case good       // 한적/맑음/안전 등 긍정
    case normal     // 보통
    case caution    // 붐빔/나쁨/주의
    case neutral    // 정보성(개수 등)
}

/// 모든 카드가 공유하는 표시 모델 — 서비스가 생성, 카드 뷰가 렌더.
/// 카드별 값 타입을 따로 두지 않고 이 한 모델로 통일(YAGNI).
struct CardContent: Sendable {
    /// 핵심 한 줄 값 (예: "한적", "보통(32)", "지하철 도보 4분")
    let headline: String
    /// 보조 설명 (예: "반경 300m 내 5곳 · 최근접 80m")
    let detail: String?
    /// 강조 배지 (없으면 nil)
    let badge: CardBadgeLevel?

    init(headline: String, detail: String? = nil, badge: CardBadgeLevel? = nil) {
        self.headline = headline
        self.detail = detail
        self.badge = badge
    }
}

/// 카드별 로딩 상태 — 카드마다 독립(부분 실패 격리, FR-010)
enum CardState: Sendable {
    case loading
    case loaded(CardContent)
    case failed
}

/// 한 인사이트 카드 = 종류 + 상태 + (실시간) 데이터 기준 시각
struct InsightCard: Sendable, Identifiable {
    let kind: InsightCardKind
    var state: CardState
    /// 실시간 카드의 데이터 기준 시각 → '○분 전' 표시 (FR-016). 없으면 nil
    var asOf: Date?

    var id: String { kind.rawValue }

    init(kind: InsightCardKind, state: CardState = .loading, asOf: Date? = nil) {
        self.kind = kind
        self.state = state
        self.asOf = asOf
    }
}
