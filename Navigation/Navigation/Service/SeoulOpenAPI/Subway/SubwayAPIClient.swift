import Foundation
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "SubwayAPI")

/// 지하철 실시간 도착 API (swopenAPI.seoul.go.kr)
final class SubwayAPIClient {

    static let shared = SubwayAPIClient()

    private let session: URLSession
    private var apiKey: String {
        Bundle.main.infoDictionary?["SEOUL_OPEN_API_KEY"] as? String ?? ""
    }
    private let baseURL = "http://swopenAPI.seoul.go.kr/api/subway"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 실시간 도착 정보 (역명 기준)

    func fetchArrivals(stationName: String) async throws -> [SubwayArrival] {
        logger.info("Fetching arrivals for station=\(stationName)")
        guard !apiKey.isEmpty else { throw SubwayAPIError.missingAPIKey }

        let encoded = stationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationName
        let urlString = "\(baseURL)/\(apiKey)/json/realtimeStationArrival/0/30/\(encoded)"
        guard let url = URL(string: urlString) else { throw SubwayAPIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validateHTTP(response)

        let decoded = try JSONDecoder().decode(SubwayArrivalResponse.self, from: data)
        let arrivals = decoded.toArrivals()
        logger.info("Arrivals fetched: \(arrivals.count) trains for station=\(stationName)")
        return arrivals
    }

    // MARK: - Private

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SubwayAPIError.network("HTTP error")
        }
    }
}

// MARK: - Response Models

private struct SubwayArrivalResponse: Decodable {
    struct RealtimeArrivalList: Decodable {
        let subwayId: String?       // 노선 ID (1호선=1001, 2호선=1002 ...)
        let trainLineNm: String?    // "성수행 - 외선순환"
        let barvlDt: String?        // 도착까지 초
        let arvlMsg2: String?       // "2분 후", "곧 도착", "진입"
        let arvlMsg3: String?       // 목적지
        let arvlCd: String?         // 도착 코드
        let updnLine: String?       // 0=상행/내선, 1=하행/외선
        let btrainNo: String?       // 열차번호 (급행 판별)
    }

    let realtimeArrivalList: [RealtimeArrivalList]?

    func toArrivals() -> [SubwayArrival] {
        guard let items = realtimeArrivalList else { return [] }
        return items.compactMap { item in
            guard let subwayId = item.subwayId else { return nil }
            let lineName = lineNameFrom(id: subwayId)
            let direction = directionFrom(updnLine: item.updnLine, subwayId: subwayId)

            // recptnDt 보정 없이 arvlMsg2 그대로 사용 (초 단위 barvlDt는 참고용)
            let arrivalMessage = item.arvlMsg2 ?? "-"
            let destination = item.arvlMsg3 ?? item.trainLineNm ?? ""
            let isExpress = item.btrainNo?.contains("급행") ?? false

            return SubwayArrival(
                lineName: lineName,
                direction: direction,
                destination: destination,
                arrivalMessage: arrivalMessage,
                isExpress: isExpress
            )
        }
    }

    private func lineNameFrom(id: String) -> String {
        switch id {
        case "1001": return "1호선"
        case "1002": return "2호선"
        case "1003": return "3호선"
        case "1004": return "4호선"
        case "1005": return "5호선"
        case "1006": return "6호선"
        case "1007": return "7호선"
        case "1008": return "8호선"
        case "1009": return "9호선"
        default: return id
        }
    }

    private func directionFrom(updnLine: String?, subwayId: String) -> String {
        // 2호선은 내선/외선
        if subwayId == "1002" {
            return updnLine == "0" ? "내선" : "외선"
        }
        return updnLine == "0" ? "상행" : "하행"
    }
}

// MARK: - SubwayAPIError

enum SubwayAPIError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "SEOUL_OPEN_API_KEY가 설정되지 않았습니다"
        case .invalidURL: return "잘못된 URL"
        case .network(let msg): return "네트워크 오류: \(msg)"
        }
    }
}
