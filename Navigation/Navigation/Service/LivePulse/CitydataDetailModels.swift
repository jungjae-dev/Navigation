import Foundation

/// 풀 `citydata` 응답 (마커 탭 시 1곳만 호출 — 인구 상세 + 날씨/대기 + 주차/따릉이)
struct CitydataFullResponse: Decodable {
    let cityData: CitydataDetail?
    enum CodingKeys: String, CodingKey { case cityData = "CITYDATA" }
}

struct CitydataDetail: Decodable {
    let areaName: String
    private let pplArr: [Population]?
    private let weatherArr: [Weather]?
    let parking: [Parking]?
    let bike: [Bike]?

    var population: Population? { pplArr?.first }
    var weather: Weather? { weatherArr?.first }

    enum CodingKeys: String, CodingKey {
        case areaName = "AREA_NM"
        case pplArr = "LIVE_PPLTN_STTS"
        case weatherArr = "WEATHER_STTS"
        case parking = "PRK_STTS"
        case bike = "SBIKE_STTS"
    }

    /// 인구 구성 (성별·연령·상주/방문) — `_ppltn`엔 없는 상세 분포
    struct Population: Decodable {
        let maleRate, femaleRate, resntRate, nonResntRate: String?
        let r0, r10, r20, r30, r40, r50, r60, r70: String?
        enum CodingKeys: String, CodingKey {
            case maleRate = "MALE_PPLTN_RATE", femaleRate = "FEMALE_PPLTN_RATE"
            case resntRate = "RESNT_PPLTN_RATE", nonResntRate = "NON_RESNT_PPLTN_RATE"
            case r0 = "PPLTN_RATE_0", r10 = "PPLTN_RATE_10", r20 = "PPLTN_RATE_20", r30 = "PPLTN_RATE_30"
            case r40 = "PPLTN_RATE_40", r50 = "PPLTN_RATE_50", r60 = "PPLTN_RATE_60", r70 = "PPLTN_RATE_70"
        }
        /// (라벨, 비율) 정렬 — 큰 순
        var ageBreakdown: [(label: String, rate: Double)] {
            let pairs: [(String, String?)] = [
                ("10대", r10), ("20대", r20), ("30대", r30), ("40대", r40),
                ("50대", r50), ("60대", r60), ("70대+", r70),
            ]
            return pairs.compactMap { l, v in v.flatMap(Double.init).map { (l, $0) } }
                .sorted { $0.rate > $1.rate }
        }
    }

    struct Weather: Decodable {
        let temp, precipitation, pcpMsg: String?
        let pm10, pm10Index, pm25, pm25Index, uvIndex, uvLevel, airMsg: String?
        enum CodingKeys: String, CodingKey {
            case temp = "TEMP", precipitation = "PRECIPITATION", pcpMsg = "PCP_MSG"
            case pm10 = "PM10", pm10Index = "PM10_INDEX", pm25 = "PM25", pm25Index = "PM25_INDEX"
            case uvIndex = "UV_INDEX", uvLevel = "UV_INDEX_LVL", airMsg = "AIR_MSG"
        }
    }

    struct Parking: Decodable { let name: String?; enum CodingKeys: String, CodingKey { case name = "PRK_NM" } }

    struct Bike: Decodable {
        let parkingCnt: String?
        enum CodingKeys: String, CodingKey { case parkingCnt = "SBIKE_PARKING_CNT" }
    }

    /// 주변 따릉이 거치 가능 대수 합
    var bikeAvailable: Int { (bike ?? []).compactMap { $0.parkingCnt.flatMap(Int.init) }.reduce(0, +) }
    var parkingLotCount: Int { parking?.count ?? 0 }
}
