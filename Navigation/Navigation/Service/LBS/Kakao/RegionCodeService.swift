import Foundation
import CoreLocation
import OSLog

private let regionLogger = Logger(subsystem: "nav.insight", category: "Region")

enum RegionCodeError: Error {
    case notFound
    case outsideSeoul
}

/// 좌표 → 행정동/자치구 (Kakao coord2regioncode). 서울만 허용.
final class RegionCodeService {

    func regionCode(at coordinate: CLLocationCoordinate2D) async throws -> RegionCode {
        let queryItems = [
            URLQueryItem(name: "x", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "y", value: "\(coordinate.latitude)"),
        ]

        let response: KakaoRegionResponse = try await KakaoAPIClient.shared.request(
            baseURL: KakaoAPIConfig.BaseURL.local,
            path: "/v2/local/geo/coord2regioncode.json",
            queryItems: queryItems,
            apiKey: KakaoAPIConfig.restAPIKey
        )

        // 행정동(H) 우선, 없으면 첫 문서
        guard let doc = response.documents.first(where: { $0.regionType == "H" })
                ?? response.documents.first else {
            throw RegionCodeError.notFound
        }

        guard doc.region1.contains("서울") else {
            regionLogger.debug("outside Seoul: \(doc.region1, privacy: .public)")
            throw RegionCodeError.outsideSeoul
        }

        let region = RegionCode(
            guName: doc.region2,
            dongName: doc.region3,
            guCode: String(doc.code.prefix(5)),
            dongCode: doc.code
        )
        regionLogger.debug("region resolved: \(region.displayAddress, privacy: .public)")
        return region
    }
}
