import Foundation
import CoreLocation
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusAPI")

/// 버스 실시간 도착 + 노선 정보 API (ws.bus.go.kr)
final class BusAPIClient {

    static let shared = BusAPIClient()

    private let session: URLSession
    private var apiKey: String {
        Bundle.main.infoDictionary?["BUS_API_KEY"] as? String ?? ""
    }
    private let baseURL = "http://ws.bus.go.kr/api/rest"

    // 인메모리 캐시
    private var routeStopsCache: [String: [BusRouteStop]] = [:]
    private var routePolylineCache: [String: [CLLocationCoordinate2D]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 정류소 실시간 도착 (arsId 기준)

    func fetchArrivals(arsId: String) async throws -> [BusArrival] {
        let key = apiKey
        logger.debug("[BusAPI] apiKey isEmpty=\(key.isEmpty), length=\(key.count)")
        logger.info("Fetching arrivals for arsId=\(arsId)")
        guard !key.isEmpty else { throw BusAPIError.missingAPIKey }

        let urlString = "\(baseURL)/stationinfo/getStationByUid?serviceKey=\(apiKey)&arsId=\(arsId)&resultType=json"
        guard let url = URL(string: urlString) else { throw BusAPIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
        logger.debug("[BusAPI] arrivals HTTP status=\(httpStatus), bytes=\(data.count)")
        try validateHTTP(response)

        if let raw = String(data: data.prefix(300), encoding: .utf8) {
            logger.debug("[BusAPI] arrivals raw(300): \(raw)")
        }
        let decoded = try JSONDecoder().decode(BusArrivalResponse.self, from: data)
        if let header = decoded.comMsgHeader {
            logger.debug("[BusAPI] arrivals errCode=\(header.errCode ?? "nil") errMsg=\(header.errMsg ?? "nil")")
        }
        let arrivals = try decoded.toArrivals()
        logger.info("Arrivals fetched: \(arrivals.count) routes for arsId=\(arsId)")
        return arrivals
    }

    // MARK: - 노선 경유 정류소 목록 (캐시 포함)

    func fetchRouteStops(routeId: String) async throws -> [BusRouteStop] {
        if let cached = routeStopsCache[routeId] {
            logger.info("Route stops cache hit: routeId=\(routeId)")
            return cached
        }
        logger.info("Fetching route stops for routeId=\(routeId)")
        guard !apiKey.isEmpty else { throw BusAPIError.missingAPIKey }

        let urlString = "\(baseURL)/busRouteInfo/getStaionByRoute?serviceKey=\(apiKey)&busRouteId=\(routeId)&resultType=json"
        guard let url = URL(string: urlString) else { throw BusAPIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validateHTTP(response)

        let decoded = try JSONDecoder().decode(BusRouteStopsResponse.self, from: data)
        let stops = decoded.toStops()
        logger.info("Route stops fetched: \(stops.count) stops for routeId=\(routeId)")
        routeStopsCache[routeId] = stops
        return stops
    }

    // MARK: - 노선별 실시간 차량 위치 (buspos/getBusPosByRtid)

    /// 노선의 현재 운행 차량 위치 (1회 조회). 서비스 미구독 시 빈 배열 반환.
    func fetchBusPositions(routeId: String) async throws -> [BusVehicle] {
        let key = apiKey
        guard !key.isEmpty else { throw BusAPIError.missingAPIKey }

        let urlString = "\(baseURL)/buspos/getBusPosByRtid?serviceKey=\(key)&busRouteId=\(routeId)&resultType=json"
        guard let url = URL(string: urlString) else { throw BusAPIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validateHTTP(response)

        let decoded = try JSONDecoder().decode(BusPositionResponse.self, from: data)
        if let header = decoded.msgHeader, header.headerCd != "0" {
            logger.warning("[BusAPI] busPos header: \(header.headerMsg ?? "") code=\(header.headerCd ?? "")")
        }
        let vehicles = decoded.toVehicles()
        logger.info("[BusAPI] busPos fetched: \(vehicles.count) vehicles for routeId=\(routeId)")
        return vehicles
    }

    // MARK: - 노선 폴리라인 (정류소 좌표 기반)

    func fetchRoutePolyline(routeId: String) async throws -> [CLLocationCoordinate2D] {
        if let cached = routePolylineCache[routeId] {
            logger.info("Polyline cache hit: routeId=\(routeId)")
            return cached
        }
        let stops = try await fetchRouteStops(routeId: routeId)
        let coords = stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        logger.info("Polyline fetched: \(coords.count) points for routeId=\(routeId)")
        routePolylineCache[routeId] = coords
        return coords
    }

    // MARK: - 버스 시간표 (디스크 캐시)

    enum DayType: String { case weekday = "1", saturday = "2", sunday = "3" }

    func fetchTimetable(arsId: String, routeId: String, dayType: DayType) async throws -> [String] {
        let cacheKey = "\(arsId)_\(routeId)_\(dayType.rawValue)"
        if let cached = loadTimetableFromDisk(key: cacheKey) {
            logger.info("Timetable cache hit (disk): \(cacheKey)")
            return cached
        }
        logger.info("Fetching timetable OA-101 style: arsId=\(arsId) routeId=\(routeId)")
        guard !apiKey.isEmpty else { throw BusAPIError.missingAPIKey }

        let urlString = "\(baseURL)/timetable/getTimeTableByStopStation?serviceKey=\(apiKey)&arsId=\(arsId)&busRouteId=\(routeId)&stDay=\(dayType.rawValue)&resultType=json"
        guard let url = URL(string: urlString) else { throw BusAPIError.invalidURL }

        let (data, response) = try await session.data(from: url)
        try validateHTTP(response)

        let decoded = try JSONDecoder().decode(BusTimetableResponse.self, from: data)
        let times = decoded.toTimes()
        logger.info("Timetable fetched: \(times.count) entries, saved to disk")
        saveTimetableToDisk(times, key: cacheKey)
        return times
    }

    // MARK: - 시간표 캐시 I/O

    private var timetableDir: URL {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("transit_data/bus_timetable")
    }

    private func loadTimetableFromDisk(key: String) -> [String]? {
        let file = timetableDir.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private func saveTimetableToDisk(_ times: [String], key: String) {
        try? FileManager.default.createDirectory(at: timetableDir, withIntermediateDirectories: true)
        let file = timetableDir.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(times) {
            try? data.write(to: file)
        }
    }

    // MARK: - Private

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BusAPIError.network("HTTP error")
        }
    }
}

// MARK: - Response Models

private struct BusArrivalResponse: Decodable {
    struct MsgBody: Decodable {
        struct ItemList: Decodable {
            let busRouteId: String?
            let busRouteAbrv: String?
            let adirection: String?
            let arrmsg1: String?
            let arrmsg2: String?
            let routeType: String?
            let isLast1: String?
            let firstTm: String?
            let lastTm: String?
            let term: String?
        }
        let itemList: [ItemList]?
    }
    struct ComMsgHeader: Decodable {
        let errCode: String?
        let errMsg: String?
    }
    let msgBody: MsgBody?
    let comMsgHeader: ComMsgHeader?

    func toArrivals() throws -> [BusArrival] {
        guard let items = msgBody?.itemList else { return [] }
        return items.compactMap { item in
            guard let routeId = item.busRouteId, !routeId.isEmpty else { return nil }
            let routeType = BusRouteType(rawValue: Int(item.routeType ?? "0") ?? 0) ?? .unknown
            return BusArrival(
                routeId: routeId,
                routeName: item.busRouteAbrv ?? "",
                direction: item.adirection ?? "",
                firstArrivalMessage: item.arrmsg1 ?? "-",
                secondArrivalMessage: item.arrmsg2 ?? "-",
                routeType: routeType,
                isLastBus: item.isLast1 == "1",
                firstTime: (item.firstTm ?? "").trimmingCharacters(in: .whitespaces),
                lastTime: (item.lastTm ?? "").trimmingCharacters(in: .whitespaces),
                term: (item.term ?? "").trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

private struct BusRouteStopsResponse: Decodable {
    struct MsgBody: Decodable {
        struct ItemList: Decodable {
            let station: String?      // 정류소 고유 ID (API 필드명: station)
            let stationNm: String?
            let arsId: String?
            let gpsX: String?
            let gpsY: String?
            let seq: String?
            let direction: String?    // 진행 방향(종착지 표시) — 회차 지점에서 값이 바뀜
        }
        let itemList: [ItemList]?
    }
    let msgBody: MsgBody?

    func toStops() -> [BusRouteStop] {
        guard let items = msgBody?.itemList else { return [] }
        return items.compactMap { item in
            guard let stId = item.station,
                  let lat = Double(item.gpsY ?? ""),
                  let lng = Double(item.gpsX ?? "") else { return nil }
            return BusRouteStop(
                stationId: stId,
                arsId: item.arsId ?? "",
                name: item.stationNm ?? "",
                seq: Int(item.seq ?? "0") ?? 0,
                lat: lat,
                lng: lng,
                direction: item.direction ?? ""
            )
        }
        .sorted { $0.seq < $1.seq }
    }
}

private struct BusTimetableResponse: Decodable {
    struct MsgBody: Decodable {
        struct ItemList: Decodable {
            let arrTime: String?
        }
        let itemList: [ItemList]?
    }
    let msgBody: MsgBody?

    func toTimes() -> [String] {
        guard let items = msgBody?.itemList else { return [] }
        return items.compactMap { $0.arrTime }.filter { !$0.isEmpty }
    }
}

private struct BusPositionResponse: Decodable {
    struct MsgHeader: Decodable {
        let headerCd: String?
        let headerMsg: String?
    }
    struct MsgBody: Decodable {
        struct ItemList: Decodable {
            let vehId: String?
            let plainNo: String?    // 차량 번호판
            let gpsX: String?       // 경도
            let gpsY: String?       // 위도
            let sectOrd: String?    // 구간 순번 (정류소 seq 매칭용)
            let busType: String?    // "1" 이면 저상버스
            let congetion: String?  // 혼잡도 (API 철자 그대로)
            let dataTm: String?     // 데이터 제공 시각
        }
        let itemList: [ItemList]?
    }
    let msgHeader: MsgHeader?
    let msgBody: MsgBody?

    func toVehicles() -> [BusVehicle] {
        guard let items = msgBody?.itemList else { return [] }
        return items.compactMap { item in
            guard let id = item.vehId,
                  let lat = Double(item.gpsY ?? ""),
                  let lng = Double(item.gpsX ?? ""),
                  lat != 0, lng != 0 else { return nil }
            return BusVehicle(
                id: id,
                plateNo: item.plainNo ?? "",
                lat: lat,
                lng: lng,
                sectionOrder: Int(item.sectOrd ?? "0") ?? 0,
                isLowFloor: item.busType == "1",
                dataTime: item.dataTm ?? ""
            )
        }
    }
}

// MARK: - BusRouteStop

struct BusRouteStop: Identifiable {
    let stationId: String
    let arsId: String
    let name: String
    let seq: Int
    let lat: Double
    let lng: Double
    /// 진행 방향(종착지 표시). 회차 지점에서 값이 바뀌어 상/하행 구분에 사용
    let direction: String

    var id: String { stationId }
}

// MARK: - BusVehicle (실시간 차량 위치)

struct BusVehicle: Identifiable {
    let id: String          // vehId
    let plateNo: String
    let lat: Double
    let lng: Double
    let sectionOrder: Int
    let isLowFloor: Bool
    let dataTime: String

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

// MARK: - BusAPIError

enum BusAPIError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case network(String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "BUS_API_KEY가 설정되지 않았습니다"
        case .invalidURL: return "잘못된 URL"
        case .network(let msg): return "네트워크 오류: \(msg)"
        case .decoding(let err): return "디코딩 오류: \(err.localizedDescription)"
        }
    }
}
