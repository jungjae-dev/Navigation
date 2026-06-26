import Foundation
import CoreLocation

/// 예측 1점 (표시용)
struct CongestionForecastPoint: Sendable {
    let time: String
    let level: CongestionLevel
    let pplMin: Int?
    let pplMax: Int?
}

/// 한 핫스팟의 표시 단위 — citydata 응답 + 번들 좌표 병합 (data-model §1)
struct CongestionPlace: Sendable, Identifiable {
    let areaName: String
    let coordinate: CLLocationCoordinate2D
    let liveLevel: CongestionLevel
    let baseTime: String          // PPLTN_TIME (신선도, FR-003)
    let pplMin: Int?
    let pplMax: Int?
    let forecast: [CongestionForecastPoint]

    var id: String { areaName }

    /// 슬라이더 offset → 표시 단계. 0=실시간, N=예측 N시간 뒤. 범위 밖이면 unknown(중립).
    func level(atOffset offset: Int) -> CongestionLevel {
        guard offset > 0 else { return liveLevel }
        let idx = offset - 1
        return idx < forecast.count ? forecast[idx].level : .unknown
    }

    /// 이 장소가 제공하는 예측 시간 수 (슬라이더 최대 산정용)
    var forecastCount: Int { forecast.count }
}
