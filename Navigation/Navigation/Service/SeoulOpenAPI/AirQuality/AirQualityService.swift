import Foundation

/// 자치구 단위 실시간 대기질 → 카드 표시 모델
final class AirQualityService {

    // 응답 필드명이 데이터셋별로 다를 수 있어 후보 키로 조회
    private let districtKeys = ["MSRSTN_NM", "SAREA_NM", "MSRSTE_NM", "SITE_NM"]
    private let gradeKeys = ["CAI_GRD", "IDEX_NM", "GRADE"]
    private let indexKeys = ["CAI_IDX", "IDEX_MVL", "KHAI"]

    /// 자치구명으로 해당 대기질을 조회해 CardContent 생성
    func airQuality(gu: String) async throws -> CardContent {
        print("[Insight] 6. RealtimeCityAir fetch (gu=\(gu))…")
        let response: RealtimeCityAirResponse = try await SeoulAPIClient.shared.request(
            service: "RealtimeCityAir",
            startIndex: 1,
            endIndex: 25,
            responseType: RealtimeCityAirResponse.self
        )

        let rows = response.container.row ?? []
        print("[Insight] 7. air rows=\(rows.count) keys=\(rows.first?.fields.keys.sorted() ?? [])")

        let match = rows.first { row in
            guard let d = pick(row, districtKeys) else { return false }
            return d.contains(gu) || gu.contains(d)
        } ?? rows.first

        guard let row = match else {
            print("[Insight] 7b. no rows")
            throw SeoulAPIError.network("대기질 데이터 없음")
        }

        let district = pick(row, districtKeys) ?? "?"
        let grade = Self.normalizeGrade(pick(row, gradeKeys))
        let indexRaw = pick(row, indexKeys)
        let valueText: String = {
            guard let raw = indexRaw else { return "" }
            if let d = Double(raw) { return " (\(Int(d)))" }
            return " (\(raw))"
        }()
        print("[Insight] 8. matched=\(district) grade=\(grade)\(valueText)")

        return CardContent(
            headline: "\(grade)\(valueText)",
            detail: "\(gu) 통합대기환경지수",
            badge: Self.badge(for: grade)
        )
    }

    private func pick(_ row: RealtimeCityAirResponse.Row, _ keys: [String]) -> String? {
        for key in keys {
            if let v = row.fields[key], !v.isEmpty { return v }
        }
        return nil
    }

    /// 등급이 숫자코드(1~4)로 오면 텍스트로 변환
    private static func normalizeGrade(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "정보 없음" }
        switch raw {
        case "1": return "좋음"
        case "2": return "보통"
        case "3": return "나쁨"
        case "4": return "매우나쁨"
        default:  return raw
        }
    }

    private static func badge(for grade: String) -> CardBadgeLevel {
        switch grade {
        case "좋음":            return .good
        case "보통":            return .normal
        case "나쁨", "매우나쁨": return .caution
        default:               return .neutral
        }
    }
}
