import UIKit

/// 혼잡 단계 (citydata `AREA_CONGEST_LVL` / `FCST_CONGEST_LVL`)
/// 원문 표기에 공백 변형("약간 붐빔")이 있어 공백 제거 후 매칭.
enum CongestionLevel: Int, CaseIterable, Sendable {
    case relaxed = 0       // 여유
    case normal = 1        // 보통
    case slightlyBusy = 2  // 약간 붐빔
    case busy = 3          // 붐빔
    case unknown = -1      // 결측/미상 → 표시 안 함/중립

    init(rawText: String) {
        switch rawText.replacingOccurrences(of: " ", with: "") {
        case "붐빔": self = .busy
        case "약간붐빔": self = .slightlyBusy
        case "보통": self = .normal
        case "여유": self = .relaxed
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .relaxed: return "여유"
        case .normal: return "보통"
        case .slightlyBusy: return "약간 붐빔"
        case .busy: return "붐빔"
        case .unknown: return "정보 없음"
        }
    }

    /// 표시 대상 여부 (unknown은 마커 미표시, FR-011)
    var isDisplayable: Bool { self != .unknown }

    /// 마커 색 (FR-013 — 디자인 토큰화는 T022 Polish에서 Theme.Palette 경유로 정리)
    var markerColor: UIColor {
        switch self {
        case .busy: return .systemRed
        case .slightlyBusy: return .systemOrange
        case .normal: return .systemYellow
        case .relaxed: return .systemGreen
        case .unknown: return .systemGray
        }
    }
}
