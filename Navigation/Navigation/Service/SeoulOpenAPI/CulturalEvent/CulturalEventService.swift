import Foundation
import CoreLocation

/// 주변 문화행사 → 카드 표시 모델
final class CulturalEventService {

    // 응답 필드명이 불확실 → 후보 키로 조회 (첫 로그에서 실제 키 확인 후 보정)
    private let titleKeys = ["TITLE", "CODENAME"]
    private let guKeys = ["GUNAME", "GU_NM"]
    private let latKeys = ["LAT", "Y_COORD", "Y"]
    private let lngKeys = ["LOT", "X_COORD", "X"]

    /// 핀 주변 행사 개수 + 대표 1건. 좌표가 있으면 반경, 없으면 자치구 매칭.
    func events(near coordinate: CLLocationCoordinate2D, gu: String, radius: CLLocationDistance = 2000) async throws -> CardContent {
        print("[Insight] E1. culturalEventInfo fetch (gu=\(gu))…")
        let response: CulturalEventResponse = try await SeoulAPIClient.shared.request(
            service: "culturalEventInfo",
            startIndex: 1,
            endIndex: 200,
            responseType: CulturalEventResponse.self
        )

        let rows = response.container.row ?? []
        print("[Insight] E2. event rows=\(rows.count) keys=\(rows.first?.fields.keys.sorted() ?? [])")

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // (행사 행, 거리) — 좌표 없으면 자치구 폴백(거리 무한대)
        let nearby: [(row: CulturalEventResponse.Row, dist: CLLocationDistance)] = rows.compactMap { row in
            // LAT/LOT 이름을 믿지 않고 값 범위로 위도/경도 판별(서울 API LAT↔LOT 뒤바뀜 대응)
            let a = pick(row, latKeys).flatMap(Double.init)
            let b = pick(row, lngKeys).flatMap(Double.init)
            if let c = Self.resolveSeoulCoord(a, b) {
                let d = origin.distance(from: CLLocation(latitude: c.lat, longitude: c.lng))
                return d <= radius ? (row, d) : nil
            }
            if let g = pick(row, guKeys), g.contains(gu) || gu.contains(g) {
                return (row, .greatestFiniteMagnitude)
            }
            return nil
        }.sorted { $0.dist < $1.dist }

        let nearestText = nearby.first.map { $0.dist.isFinite ? "\(Int($0.dist))m" : "구매칭" } ?? "-"
        print("[Insight] E3. nearby events=\(nearby.count) nearest=\(nearestText)")
        guard let nearest = nearby.first else {
            return CardContent(headline: "주변 행사 없음", badge: .neutral)
        }

        let sample = pick(nearest.row, titleKeys)
        return CardContent(
            headline: "행사 \(nearby.count)건",
            detail: sample.map { "예: \($0)" },
            badge: .neutral
        )
    }

    /// 두 값 중 위도(33~39)·경도(124~132) 범위로 좌표 판별 (LAT↔LOT 뒤바뀜 대응)
    private static func resolveSeoulCoord(_ a: Double?, _ b: Double?) -> (lat: Double, lng: Double)? {
        let vals = [a, b].compactMap { $0 }.filter { $0 != 0 }
        guard let lat = vals.first(where: { (33.0...39.0).contains($0) }),
              let lng = vals.first(where: { (124.0...132.0).contains($0) }) else { return nil }
        return (lat, lng)
    }

    private func pick(_ row: CulturalEventResponse.Row, _ keys: [String]) -> String? {
        for key in keys {
            if let v = row.fields[key], !v.isEmpty { return v }
        }
        return nil
    }
}
