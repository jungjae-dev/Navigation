import Foundation

struct KakaoGeocodingResponse: Decodable, Sendable {
    let meta: Meta
    let documents: [Document]

    struct Meta: Decodable, Sendable {
        let totalCount: Int

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
        }
    }

    struct Document: Decodable, Sendable {
        let address: Address?
        let roadAddress: RoadAddress?

        enum CodingKeys: String, CodingKey {
            case address
            case roadAddress = "road_address"
        }
    }

    struct Address: Decodable, Sendable {
        let addressName: String

        enum CodingKeys: String, CodingKey {
            case addressName = "address_name"
        }
    }

    struct RoadAddress: Decodable, Sendable {
        let addressName: String

        enum CodingKeys: String, CodingKey {
            case addressName = "address_name"
        }
    }
}
