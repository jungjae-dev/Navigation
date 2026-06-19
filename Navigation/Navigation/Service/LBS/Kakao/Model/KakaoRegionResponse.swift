import Foundation

/// Kakao Local `coord2regioncode` 응답 (좌표 → 행정구역)
struct KakaoRegionResponse: Decodable {
    struct Document: Decodable {
        let regionType: String   // "H"(행정동) / "B"(법정동)
        let region1: String      // 시·도
        let region2: String      // 자치구
        let region3: String      // 행정동/법정동
        let code: String         // 지역 코드

        enum CodingKeys: String, CodingKey {
            case regionType = "region_type"
            case region1 = "region_1depth_name"
            case region2 = "region_2depth_name"
            case region3 = "region_3depth_name"
            case code
        }
    }

    let documents: [Document]
}
