import Foundation
import CoreLocation

/// 따릉이 정류소 모델 (서비스 레이어용 단일 표현)
/// OA-15493 응답을 디코딩 후 변환된 형태
struct BikeStation: Hashable, Sendable {
    let stationId: String
    let stationName: String
    let coordinate: CLLocationCoordinate2D
    let totalRacks: Int          // rackTotCnt — 거치대 총 개수
    let availableBikes: Int      // parkingBikeTotCnt — 대여 가능 자전거 수
    let shared: Int              // 거치율 (%)

    /// 반납 가능한 빈 거치대 수
    var availableRacks: Int { max(0, totalRacks - availableBikes) }
}

extension BikeStation {
    // stationId 가 unique 하므로 식별성만으로 충분 — 데이터 변경 감지는 removeDuplicates(by:) 등에서 명시
    static func == (lhs: BikeStation, rhs: BikeStation) -> Bool {
        lhs.stationId == rhs.stationId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stationId)
    }
}
