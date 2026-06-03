import Foundation
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "SubwayTimetable")

/// 지하철 시간표 API — 서울 열린데이터광장 OA-101
/// openapi.seoul.go.kr:8088/{KEY}/json/SearchSTNTimeTableByIDService/{start}/{end}/{stationCode}/{dayType}/{upDown}
final class SubwayTimetableAPI {

    static let shared = SubwayTimetableAPI()

    private let client: SeoulAPIClient

    init(client: SeoulAPIClient = .shared) {
        self.client = client
    }

    // MARK: - 시간표 조회 (디스크 캐시)

    enum Direction: String { case up = "1", down = "2" }
    enum DayType: String { case weekday = "1", saturday = "2", sunday = "3" }

    struct TimetableEntry: Codable {
        let departureTime: String   // "HH:MM" 형식
        let destination: String
    }

    func fetchTimetable(
        stationCode: String,
        direction: Direction,
        dayType: DayType
    ) async throws -> [TimetableEntry] {
        let cacheKey = "\(stationCode)_\(direction.rawValue)_\(dayType.rawValue)"

        if let cached = loadFromDisk(key: cacheKey) {
            logger.info("Timetable cache hit (disk): \(cacheKey)")
            return cached
        }

        logger.info("Fetching timetable OA-101: station=\(stationCode) dir=\(direction.rawValue) day=\(dayType.rawValue)")

        let response: SubwayTimetableResponse = try await client.request(
            service: "SearchSTNTimeTableByIDService",
            startIndex: 1,
            endIndex: 200,
            extraPaths: [stationCode, dayType.rawValue, direction.rawValue],
            responseType: SubwayTimetableResponse.self
        )

        let entries = response.toEntries()
        logger.info("Timetable fetched: \(entries.count) entries, saved to disk")
        saveToDisk(entries, key: cacheKey)
        return entries
    }

    // MARK: - 디스크 캐시

    private var cacheDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("transit_data/subway_timetable")
    }

    private func loadFromDisk(key: String) -> [TimetableEntry]? {
        let file = cacheDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([TimetableEntry].self, from: data)
    }

    private func saveToDisk(_ entries: [TimetableEntry], key: String) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let file = cacheDir.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: file)
        }
    }
}

// MARK: - Response Model

private struct SubwayTimetableResponse: Decodable {
    struct ServiceBody: Decodable {
        struct Row: Decodable {
            let ARRIVETIME: String?
            let SUBWAYSNAME: String?
        }
        let row: [Row]?
    }

    let SearchSTNTimeTableByIDService: ServiceBody?

    func toEntries() -> [SubwayTimetableAPI.TimetableEntry] {
        guard let rows = SearchSTNTimeTableByIDService?.row else { return [] }
        return rows.compactMap { row in
            guard let time = row.ARRIVETIME else { return nil }
            let parts = time.split(separator: ":").map(String.init)
            guard parts.count >= 2 else { return nil }
            return SubwayTimetableAPI.TimetableEntry(
                departureTime: "\(parts[0]):\(parts[1])",
                destination: row.SUBWAYSNAME ?? ""
            )
        }
    }
}
