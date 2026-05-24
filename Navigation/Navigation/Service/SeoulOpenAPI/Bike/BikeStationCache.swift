import Foundation
import Combine

/// 따릉이 정류소 메모리 캐시 (싱글톤)
/// - in-memory only, 디스크 캐시 미사용
/// - 명시적 갱신만 (자동 폴링 없음)
/// - stationId Dictionary로 O(1) lookup
@MainActor
final class BikeStationCache {

    static let shared = BikeStationCache()

    /// 전체 정류소 목록 (구독 가능)
    let stations = CurrentValueSubject<[BikeStation], Never>([])

    /// 마지막 갱신 시각
    let lastUpdated = CurrentValueSubject<Date?, Never>(nil)

    private var stationsById: [String: BikeStation] = [:]

    private init() {}

    // MARK: - Lookup

    /// stationId로 단건 조회 — O(1)
    func station(id: String) -> BikeStation? {
        stationsById[id]
    }

    /// 모든 정류소 (배열)
    var allStations: [BikeStation] {
        Array(stationsById.values)
    }

    // MARK: - Update

    /// 전체 갱신 (fetchAll 결과 반영)
    func update(_ stations: [BikeStation]) {
        stationsById = Dictionary(uniqueKeysWithValues: stations.map { ($0.stationId, $0) })
        self.stations.send(stations)
        self.lastUpdated.send(Date())
    }

    /// 단건 갱신 (fetchOne 결과 반영) — 해당 stationId만 교체, 다른 항목 유지
    func update(single station: BikeStation) {
        stationsById[station.stationId] = station
        stations.send(allStations)
        lastUpdated.send(Date())
    }

    /// 캐시 비우기
    func clear() {
        stationsById.removeAll()
        stations.send([])
        lastUpdated.send(nil)
    }
}
