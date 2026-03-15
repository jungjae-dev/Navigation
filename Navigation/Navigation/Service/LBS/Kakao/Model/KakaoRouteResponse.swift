import Foundation

struct KakaoRouteResponse: Decodable, Sendable {
    let routes: [KakaoRoute]

    struct KakaoRoute: Decodable, Sendable {
        let resultCode: Int
        let resultMsg: String
        let summary: Summary?
        let sections: [Section]?

        enum CodingKeys: String, CodingKey {
            case resultCode = "result_code"
            case resultMsg = "result_msg"
            case summary, sections
        }
    }

    struct Summary: Decodable, Sendable {
        let distance: Int      // meters
        let duration: Int      // seconds
    }

    struct Section: Decodable, Sendable {
        let distance: Int
        let duration: Int
        let roads: [Road]
        let guides: [Guide]
    }

    struct Road: Decodable, Sendable {
        let vertexes: [Double] // [lng, lat, lng, lat, ...]
    }

    struct Guide: Decodable, Sendable {
        let name: String
        let x: Double
        let y: Double
        let distance: Int
        let duration: Int
        let type: Int          // turn type code
        let guidance: String   // guidance text
    }
}
