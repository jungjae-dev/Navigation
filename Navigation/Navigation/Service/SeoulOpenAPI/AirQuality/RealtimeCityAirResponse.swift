import Foundation

/// 임의 문자열 키 디코딩용
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// 서울시 실시간 자치구별 대기환경 현황 (service: "RealtimeCityAir")
/// 응답 필드명이 데이터셋별로 달라, 각 행을 키-값 사전으로 디코딩(숫자/문자 모두 String으로 보관).
struct RealtimeCityAirResponse: Decodable {
    struct Container: Decodable {
        let row: [Row]?
    }
    struct Row: Decodable {
        let fields: [String: String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKey.self)
            var dict: [String: String] = [:]
            for key in c.allKeys {
                if let s = try? c.decode(String.self, forKey: key) {
                    dict[key.stringValue] = s
                } else if let d = try? c.decode(Double.self, forKey: key) {
                    dict[key.stringValue] = String(d)
                } else if let i = try? c.decode(Int.self, forKey: key) {
                    dict[key.stringValue] = String(i)
                }
            }
            fields = dict
        }
    }

    let container: Container

    enum CodingKeys: String, CodingKey {
        case container = "RealtimeCityAir"
    }
}
