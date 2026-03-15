import Foundation

struct KakaoSearchResponse: Decodable, Sendable {
    let meta: Meta
    let documents: [Document]

    struct Meta: Decodable, Sendable {
        let totalCount: Int
        let pageableCount: Int
        let isEnd: Bool

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case pageableCount = "pageable_count"
            case isEnd = "is_end"
        }
    }

    struct Document: Decodable, Sendable {
        let placeName: String
        let addressName: String
        let roadAddressName: String?
        let phone: String?
        let categoryName: String?
        let categoryGroupName: String?
        let placeUrl: String?
        let distance: String?
        let x: String   // longitude
        let y: String   // latitude

        enum CodingKeys: String, CodingKey {
            case placeName = "place_name"
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
            case phone
            case categoryName = "category_name"
            case categoryGroupName = "category_group_name"
            case placeUrl = "place_url"
            case distance
            case x, y
        }
    }
}
