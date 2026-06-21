import Foundation
import CoreLocation

/// 최근접 공원 → 카드 표시 모델
final class GreeneryService {

    private let nameKeys = ["PARK_NM", "P_PARK", "PARK_NAME", "P_NAME"]
    private let latKeys = ["YCRD", "LAT", "Y"]
    private let lngKeys = ["XCRD", "LNT", "X"]

    // 공원은 정적 데이터 → 1일 캐시 (위치 무관 fetch + 위치별 최근접 계산)
    private static var cache: (rows: [ParkResponse.Row], at: Date)?
    private static let ttl: TimeInterval = 60 * 60 * 24

    func nearestPark(near coordinate: CLLocationCoordinate2D) async throws -> CardContent {
        let rows = try await Self.parkRows()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = rows.compactMap { row -> (name: String, dist: CLLocationDistance)? in
            let a = pick(row, latKeys).flatMap(Double.init)
            let b = pick(row, lngKeys).flatMap(Double.init)
            guard let c = Self.resolveSeoulCoord(a, b) else { return nil }
            let d = origin.distance(from: CLLocation(latitude: c.lat, longitude: c.lng))
            return (pick(row, nameKeys) ?? "공원", d)
        }.min { $0.dist < $1.dist }

        guard let nearest else {
            print("[Insight] G3. no park coords")
            return CardContent(headline: "주변 공원 정보 없음", badge: .neutral)
        }
        print("[Insight] G3. nearest park=\(nearest.name) \(Int(nearest.dist))m")

        return CardContent(
            headline: nearest.name,
            detail: "최근접 공원 · \(Self.distanceText(nearest.dist))",
            badge: .good
        )
    }

    private static func parkRows() async throws -> [ParkResponse.Row] {
        if let c = cache, Date().timeIntervalSince(c.at) < ttl {
            print("[Insight] G1. park cache hit (\(c.rows.count))")
            return c.rows
        }
        print("[Insight] G1. SearchParkInfoService fetch…")
        let response: ParkResponse = try await SeoulAPIClient.shared.request(
            service: "SearchParkInfoService",
            startIndex: 1,
            endIndex: 300,
            responseType: ParkResponse.self
        )
        let rows = response.container.row ?? []
        print("[Insight] G2. park rows=\(rows.count) keys=\(rows.first?.fields.keys.sorted() ?? [])")
        cache = (rows, Date())
        return rows
    }

    private func pick(_ row: ParkResponse.Row, _ keys: [String]) -> String? {
        for key in keys {
            if let v = row.fields[key], !v.isEmpty { return v }
        }
        return nil
    }

    private static func resolveSeoulCoord(_ a: Double?, _ b: Double?) -> (lat: Double, lng: Double)? {
        let vals = [a, b].compactMap { $0 }.filter { $0 != 0 }
        guard let lat = vals.first(where: { (33.0...39.0).contains($0) }),
              let lng = vals.first(where: { (124.0...132.0).contains($0) }) else { return nil }
        return (lat, lng)
    }

    private static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1000)
    }
}
