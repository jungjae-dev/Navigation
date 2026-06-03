import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "DataService")

/// 버스/지하철 정적 데이터 서비스
/// - version.json 확인 → 변경된 파일만 Gist에서 다운로드
/// - Documents/TransitData/ 에 캐시, 번들 fallback 제공
/// - 하루 1회 수동 갱신 지원
@MainActor
final class TransitDataService {

    static let shared = TransitDataService()

    // MARK: - State

    let statePublisher = CurrentValueSubject<TransitDataState, Never>(.loading)

    // MARK: - Private

    private let cacheDir: URL
    private let lastUpdatedKey = "transit_last_updated"

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDir = docs.appendingPathComponent("TransitData")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Load

    func load() async {
        statePublisher.send(.loading)
        do {
            try await downloadIfNeeded()
            let busStops = try loadBusStops()
            let subwayStations = try loadSubwayStations()
            let subwayLines = try loadSubwayLines()
            logger.info("Transit data loaded — busStops: \(busStops.count), stations: \(subwayStations.count)")
            statePublisher.send(.loaded(busStops: busStops, subwayStations: subwayStations, subwayLines: subwayLines))
        } catch {
            logger.warning("Gist fetch failed, using bundle fallback: \(error.localizedDescription)")
            loadFromBundle()
        }
    }

    // MARK: - Download

    private func downloadIfNeeded() async throws {
        guard let remoteVersion = try? await fetchVersion() else {
            logger.warning("version.json fetch failed — skipping download")
            return
        }

        let localVersion = loadLocalVersion()
        logger.info("version.json fetched: busStops=\(remoteVersion.busStops), stations=\(remoteVersion.subwayStations)")

        if localVersion?.busStops != remoteVersion.busStops {
            try await downloadFile(urlString: TransitGistURLs.busStops, name: "bus_stops_seoul.json")
            logger.info("bus_stops downloaded")
        } else {
            logger.info("Using cached bus_stops (version up to date)")
        }

        if localVersion?.subwayStations != remoteVersion.subwayStations {
            try await downloadFile(urlString: TransitGistURLs.subwayStations, name: "subway_stations_seoul.json")
            logger.info("subway_stations downloaded")
        } else {
            logger.info("Using cached subway_stations (version up to date)")
        }

        if localVersion?.subwayLines != remoteVersion.subwayLines {
            try await downloadFile(urlString: TransitGistURLs.subwayLines, name: "subway_lines_seoul.json")
            logger.info("subway_lines downloaded")
        } else {
            logger.info("Using cached subway_lines (version up to date)")
        }

        saveLocalVersion(remoteVersion)
    }

    private func fetchVersion() async throws -> TransitDataVersion {
        guard let url = URL(string: TransitGistURLs.version) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TransitDataVersion.self, from: data)
    }

    private func downloadFile(urlString: String, name: String) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let dest = cacheDir.appendingPathComponent(name)
        try data.write(to: dest)
    }

    // MARK: - Load Files

    private func loadBusStops() throws -> [BusStop] {
        let data = try cachedOrBundleData(name: "bus_stops_seoul")
        if let envelope = try? JSONDecoder().decode(BusStopsEnvelope.self, from: data) {
            return envelope.data
        }
        // flat array fallback (이전 포맷 호환)
        return try JSONDecoder().decode([BusStop].self, from: data)
    }

    private func loadSubwayStations() throws -> [SubwayStation] {
        let data = try cachedOrBundleData(name: "subway_stations_seoul")
        if let envelope = try? JSONDecoder().decode(SubwayStationsEnvelope.self, from: data) {
            return envelope.data
        }
        return try JSONDecoder().decode([SubwayStation].self, from: data)
    }

    private func loadSubwayLines() throws -> SubwayLines {
        let data = try cachedOrBundleData(name: "subway_lines_seoul")
        if let envelope = try? JSONDecoder().decode(SubwayLinesEnvelope.self, from: data) {
            return envelope.data
        }
        return try JSONDecoder().decode(SubwayLines.self, from: data)
    }

    private func cachedOrBundleData(name: String) throws -> Data {
        let cached = cacheDir.appendingPathComponent("\(name).json")
        if let data = try? Data(contentsOf: cached) { return data }
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw NSError(domain: "TransitDataService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "\(name).json not found"])
        }
        return data
    }

    private func loadFromBundle() {
        do {
            let busStops = try loadBusStops()
            let subwayStations = try loadSubwayStations()
            let subwayLines = try loadSubwayLines()
            statePublisher.send(.loaded(busStops: busStops, subwayStations: subwayStations, subwayLines: subwayLines))
        } catch {
            logger.error("Bundle fallback also failed: \(error.localizedDescription)")
            statePublisher.send(.failed(error.localizedDescription))
        }
    }

    // MARK: - Version Cache

    private func loadLocalVersion() -> TransitDataVersion? {
        let url = cacheDir.appendingPathComponent("version.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TransitDataVersion.self, from: data)
    }

    private func saveLocalVersion(_ version: TransitDataVersion) {
        let url = cacheDir.appendingPathComponent("version.json")
        if let data = try? JSONEncoder().encode(version) {
            try? data.write(to: url)
        }
    }

    // MARK: - Manual Refresh (T009)

    func canRefreshToday() -> Bool {
        guard let lastDate = UserDefaults.standard.object(forKey: lastUpdatedKey) as? Date else { return true }
        return !Calendar.current.isDateInToday(lastDate)
    }

    func refreshAll() async throws {
        guard canRefreshToday() else {
            logger.warning("Refresh blocked: already updated today")
            return
        }
        logger.info("Manual refresh started")
        // 강제 재다운로드를 위해 로컬 버전 삭제
        let versionFile = cacheDir.appendingPathComponent("version.json")
        try? FileManager.default.removeItem(at: versionFile)

        try await downloadIfNeeded()
        UserDefaults.standard.set(Date(), forKey: lastUpdatedKey)

        let busStops = try loadBusStops()
        let subwayStations = try loadSubwayStations()
        let subwayLines = try loadSubwayLines()
        logger.info("Manual refresh complete — busStops: \(busStops.count), stations: \(subwayStations.count)")
        statePublisher.send(.loaded(busStops: busStops, subwayStations: subwayStations, subwayLines: subwayLines))
    }

    func clearTimetableCache() {
        let timetableDir = cacheDir.appendingPathComponent("timetable")
        try? FileManager.default.removeItem(at: timetableDir)
        logger.info("Timetable cache cleared")
    }

    func lastUpdatedDate() -> Date? {
        UserDefaults.standard.object(forKey: lastUpdatedKey) as? Date
    }
}
