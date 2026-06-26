import Foundation
import MapKit
import OSLog

private let livePulseLogger = Logger(subsystem: "nav.api", category: "LivePulse")

/// 서울 실시간 도시데이터(citydata_ppltn) 장소별 호출 + TTL 캐시 + 부분 실패 허용 (research R3).
/// 좌표는 번들 HotspotCatalog에서 병합(응답에 좌표 없음, R2).
final class CitydataService {

    private let catalog: HotspotCatalog
    private let ttl: TimeInterval
    private var cache: [String: (place: CongestionPlace, at: Date)] = [:]

    init(catalog: HotspotCatalog, ttl: TimeInterval = 300) {  // 원천 갱신 ≈5분
        self.catalog = catalog
        self.ttl = ttl
    }

    /// 가시 영역(rect) 안의 핫스팟만 로딩 (FR-007a)
    func loadVisible(in rect: MKMapRect, now: Date = Date()) async -> [CongestionPlace] {
        await fetch(areaNames: catalog.visibleAreaNames(in: rect), now: now)
    }

    /// 장소별 병렬 호출. TTL 유효분은 캐시 사용, 실패 장소는 스킵(부분 실패 허용, FR-012).
    func fetch(areaNames: [String], now: Date = Date()) async -> [CongestionPlace] {
        await withTaskGroup(of: CongestionPlace?.self) { group in
            for name in areaNames {
                if let c = cache[name], now.timeIntervalSince(c.at) < ttl {
                    group.addTask { c.place }
                    continue
                }
                group.addTask { [weak self] in await self?.fetchOne(areaName: name) }
            }
            var result: [CongestionPlace] = []
            for await place in group {
                if let place {
                    result.append(place)
                    cache[place.areaName] = (place, now)
                }
            }
            return result
        }
    }

    private func fetchOne(areaName: String) async -> CongestionPlace? {
        guard let hotspot = catalog.hotspot(named: areaName) else { return nil }
        // 장소명은 한글·중점(·)·공백 포함 → path 인코딩 필수
        let encoded = areaName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? areaName
        do {
            let response: CitydataResponse = try await SeoulAPIClient.shared.request(
                service: "citydata_ppltn",
                startIndex: 1,
                endIndex: 1,
                extraPaths: [encoded],
                responseType: CitydataResponse.self
            )
            guard let raw = response.places?.first else {
                livePulseLogger.info("citydata 빈 응답: \(areaName, privacy: .public)")
                return nil
            }
            return Self.merge(raw, hotspot: hotspot)
        } catch {
            livePulseLogger.error("citydata 실패 \(areaName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func merge(_ raw: CitydataPlace, hotspot: Hotspot) -> CongestionPlace {
        let forecast = (raw.forecast ?? []).map {
            CongestionForecastPoint(
                time: $0.time,
                level: CongestionLevel(rawText: $0.level),
                pplMin: $0.pplMin.flatMap(Int.init),
                pplMax: $0.pplMax.flatMap(Int.init)
            )
        }
        return CongestionPlace(
            areaName: raw.areaName,
            coordinate: hotspot.coordinate,
            liveLevel: CongestionLevel(rawText: raw.congestLevel),
            baseTime: raw.pplTime,
            pplMin: raw.pplMin.flatMap(Int.init),
            pplMax: raw.pplMax.flatMap(Int.init),
            forecast: forecast
        )
    }
}
