import Foundation
import CoreLocation

/// OA-15493 bikeList 응답 DTO
/// 두 가지 응답 형태가 옴:
/// 1. 정상: { "rentBikeStatus": { "list_total_count": N, "RESULT": {...}, "row": [...] } }
/// 2. 에러 (INFO-200 등): { "CODE": "INFO-200", "MESSAGE": "..." }
struct BikeStationResponse: Decodable {

    let rentBikeStatus: RentBikeStatus?

    // 단독 에러 응답 (INFO-200 등)
    let CODE: String?
    let MESSAGE: String?

    struct RentBikeStatus: Decodable {
        let list_total_count: Int
        let RESULT: ResultMeta
        let row: [Row]
    }

    struct ResultMeta: Decodable {
        let CODE: String
        let MESSAGE: String
    }

    struct Row: Decodable {
        let stationId: String
        let stationName: String
        let stationLatitude: String
        let stationLongitude: String
        let rackTotCnt: String
        let parkingBikeTotCnt: String
        let shared: String

        func toModel() -> BikeStation? {
            guard let lat = Double(stationLatitude),
                  let lng = Double(stationLongitude),
                  let racks = Int(rackTotCnt),
                  let bikes = Int(parkingBikeTotCnt) else { return nil }
            let sharedValue = Int(shared) ?? 0
            return BikeStation(
                stationId: stationId,
                stationName: stationName,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                totalRacks: racks,
                availableBikes: bikes,
                shared: sharedValue
            )
        }
    }

    /// 응답을 BikeStation 배열로 변환
    /// - INFO-200: 빈 배열 반환 (에러 아님)
    /// - 기타 에러 코드: throw
    func decodeStations() throws -> [BikeStation] {
        if let status = rentBikeStatus {
            if status.RESULT.CODE == "INFO-000" {
                return status.row.compactMap { $0.toModel() }
            }
            if status.RESULT.CODE == "INFO-200" {
                return []
            }
            throw SeoulAPIError.from(code: status.RESULT.CODE, message: status.RESULT.MESSAGE)
        }
        if let code = CODE, let message = MESSAGE {
            if code == "INFO-200" { return [] }
            throw SeoulAPIError.from(code: code, message: message)
        }
        throw SeoulAPIError.decoding(NSError(domain: "BikeStationResponse", code: -1))
    }
}
