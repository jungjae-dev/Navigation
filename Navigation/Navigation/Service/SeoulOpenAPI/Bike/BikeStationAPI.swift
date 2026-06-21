import Foundation
import OSLog

private let bikeLogger = Logger(subsystem: "nav.bike", category: "API")

/// 따릉이 정류소 API (서울시 OA-15493 bikeList)
struct BikeStationAPI {

    private let client: SeoulAPIClient

    init(client: SeoulAPIClient = .shared) {
        self.client = client
    }

    /// 전체 정류소 + 실시간 잔여 자전거 정보 조회
    /// - 페이지당 1,000건 제한 → 4분할 병렬 호출 (최대 4,000건 커버)
    /// - 일부 페이지 실패 시 성공 페이지 결과는 유지
    func fetchAll() async throws -> [BikeStation] {
        let pages: [(Int, Int)] = [(1, 1000), (1001, 2000), (2001, 3000), (3001, 4000)]

        // 페이지별 실패가 다른 페이지를 취소시키지 않도록 non-throwing group + 페이지 내부에서 catch
        let results: [[BikeStation]] = await withTaskGroup(of: [BikeStation].self) { group in
            for (start, end) in pages {
                group.addTask {
                    do {
                        return try await self.fetchPage(start: start, end: end)
                    } catch {
                        print("[Bike] fetchPage \(start)-\(end) FAILED: \(error)")
                        return []
                    }
                }
            }
            var collected: [[BikeStation]] = []
            for await page in group {
                collected.append(page)
            }
            return collected
        }

        // 중복 제거 (stationId 기준)
        var dedup: [String: BikeStation] = [:]
        for stations in results {
            for s in stations {
                dedup[s.stationId] = s
            }
        }
        print("[Bike] fetchAll total=\(dedup.count)")
        return Array(dedup.values)
    }

    /// 단일 정류소 새로고침 (미문서화 패턴: bikeList/1/1/{stationId}/)
    /// - 잘못된 stationId → INFO-200 → nil 반환
    func fetchOne(stationId: String) async throws -> BikeStation? {
        let response: BikeStationResponse = try await client.request(
            service: "bikeList",
            startIndex: 1,
            endIndex: 1,
            extraPaths: [stationId],
            responseType: BikeStationResponse.self
        )
        let stations = try response.decodeStations()
        return stations.first
    }

    // MARK: - Private

    private func fetchPage(start: Int, end: Int) async throws -> [BikeStation] {
        let response: BikeStationResponse = try await client.request(
            service: "bikeList",
            startIndex: start,
            endIndex: end,
            responseType: BikeStationResponse.self
        )
        do {
            return try response.decodeStations()
        } catch SeoulAPIError.noData {
            return []
        }
    }
}
