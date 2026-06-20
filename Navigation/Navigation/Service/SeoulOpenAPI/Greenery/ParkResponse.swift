import Foundation

/// 서울시 주요 공원현황 (service: "SearchParkInfoService")
/// 필드명 불확실 → 각 행을 키-값 사전으로 디코딩(DynamicCodingKey 재사용).
struct ParkResponse: Decodable {
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
        case container = "SearchParkInfoService"
    }
}
