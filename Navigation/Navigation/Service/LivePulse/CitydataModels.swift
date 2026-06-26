import Foundation

/// 서울 실시간 도시데이터 `citydata_ppltn` 응답 (2026-06-26 실호출로 스키마 확정)
/// 숫자 필드도 문자열로 옴(예: "76000") → String 디코딩 후 변환.
struct CitydataResponse: Decodable {
    let places: [CitydataPlace]?
    let result: CitydataResult?

    enum CodingKeys: String, CodingKey {
        case places = "SeoulRtd.citydata_ppltn"
        case result = "RESULT"
    }
}

struct CitydataResult: Decodable {
    let code: String?
    let message: String?
    enum CodingKeys: String, CodingKey {
        case code = "RESULT.CODE"
        case message = "RESULT.MESSAGE"
    }
}

struct CitydataPlace: Decodable {
    let areaName: String
    let areaCode: String
    let congestLevel: String   // "붐빔" / "약간 붐빔" / "보통" / "여유"
    let congestMsg: String?
    let pplMin: String?
    let pplMax: String?
    let pplTime: String        // 기준 시각 "2026-06-26 10:20"
    let forecastYN: String?
    let forecast: [CitydataForecast]?

    enum CodingKeys: String, CodingKey {
        case areaName = "AREA_NM"
        case areaCode = "AREA_CD"
        case congestLevel = "AREA_CONGEST_LVL"
        case congestMsg = "AREA_CONGEST_MSG"
        case pplMin = "AREA_PPLTN_MIN"
        case pplMax = "AREA_PPLTN_MAX"
        case pplTime = "PPLTN_TIME"
        case forecastYN = "FCST_YN"
        case forecast = "FCST_PPLTN"
    }
}

/// 시간별 예측 1점 (응답상 12개·1시간 간격, +1h~+12h)
struct CitydataForecast: Decodable {
    let time: String           // "2026-06-26 11:00"
    let level: String          // 예측 혼잡 단계
    let pplMin: String?
    let pplMax: String?

    enum CodingKeys: String, CodingKey {
        case time = "FCST_TIME"
        case level = "FCST_CONGEST_LVL"
        case pplMin = "FCST_PPLTN_MIN"
        case pplMax = "FCST_PPLTN_MAX"
    }
}
