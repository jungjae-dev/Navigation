import Foundation
import CoreLocation

/// 동네 인사이트 카드별 데이터 집계.
/// (슬라이스 2: 대기질 + 교통(따릉이) + 지금(문화행사))
final class NeighborhoodInsightService {

    private let airQuality = AirQualityService()
    private let bikeAPI = BikeStationAPI()
    private let events = CulturalEventService()
    private let greenery = GreeneryService()

    // MARK: - 대기질

    func airQualityCard(gu: String) async -> InsightCard {
        do {
            let content = try await airQuality.airQuality(gu: gu)
            print("[Insight] card airQuality → loaded: \(content.headline)")
            return InsightCard(kind: .airQuality, state: .loaded(content), asOf: Date())
        } catch {
            print("[Insight] card airQuality → FAILED: \(error)")
            return InsightCard(kind: .airQuality, state: .failed)
        }
    }

    // MARK: - 교통 (따릉이 최근접)

    func transitCard(at coordinate: CLLocationCoordinate2D) async -> InsightCard {
        do {
            let stations = try await bikeStations()
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearest = stations.min {
                origin.distance(from: $0.location) < origin.distance(from: $1.location)
            }
            guard let station = nearest else {
                print("[Insight] card transit → no stations")
                return InsightCard(kind: .transit, state: .loaded(
                    CardContent(headline: "주변 따릉이 없음", badge: .neutral)))
            }
            let dist = origin.distance(from: station.location)
            let content = CardContent(
                headline: "따릉이 \(station.availableBikes)대 대여 가능",
                detail: "최근접 \(Self.distanceText(dist)) · \(station.stationName)",
                badge: station.availableBikes > 0 ? .good : .caution
            )
            print("[Insight] card transit → loaded: \(content.headline) (\(Self.distanceText(dist)))")
            return InsightCard(kind: .transit, state: .loaded(content), asOf: Date())
        } catch {
            print("[Insight] card transit → FAILED: \(error)")
            return InsightCard(kind: .transit, state: .failed)
        }
    }

    /// 따릉이 정류소 — 캐시 있으면 재사용, 없으면 1회 fetch 후 캐시
    @MainActor
    private func bikeStations() async throws -> [BikeStation] {
        let cached = BikeStationCache.shared.allStations
        if !cached.isEmpty {
            print("[Insight] transit: cache hit (\(cached.count))")
            return cached
        }
        print("[Insight] transit: cache miss → fetchAll…")
        let fetched = try await bikeAPI.fetchAll()
        BikeStationCache.shared.update(fetched)
        print("[Insight] transit: fetched \(fetched.count)")
        return fetched
    }

    // MARK: - 지금 (문화행사)

    func eventsCard(at coordinate: CLLocationCoordinate2D, gu: String) async -> InsightCard {
        do {
            let content = try await events.events(near: coordinate, gu: gu)
            print("[Insight] card events → loaded: \(content.headline)")
            return InsightCard(kind: .events, state: .loaded(content))
        } catch {
            print("[Insight] card events → FAILED: \(error)")
            return InsightCard(kind: .events, state: .failed)
        }
    }

    // MARK: - 녹지 (최근접 공원)

    func greeneryCard(at coordinate: CLLocationCoordinate2D) async -> InsightCard {
        do {
            let content = try await greenery.nearestPark(near: coordinate)
            print("[Insight] card greenery → loaded: \(content.headline)")
            return InsightCard(kind: .greenery, state: .loaded(content))
        } catch {
            print("[Insight] card greenery → FAILED: \(error)")
            return InsightCard(kind: .greenery, state: .failed)
        }
    }

    // MARK: - Helper

    private static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1000)
    }
}

private extension BikeStation {
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
