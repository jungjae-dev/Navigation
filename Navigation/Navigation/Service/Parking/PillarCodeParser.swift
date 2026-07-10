import Foundation

/// 기둥 코드 문자열의 파싱 결과. 순수 값 타입 — 리플레이·유닛 테스트 대상.
struct ParsedCode: Equatable, Sendable {

    /// 정규화된 원문 (구분자 통일·공백 제거·대문자화)
    let raw: String
    /// 정규화된 층 토큰 ("B2" — "지하2"도 "B2"로 정규화)
    let floorToken: String?
    let zoneToken: String?
    /// 구역의 서수 인덱스 (A=0…, 가=0…) — 격자 축 계산 입력
    let zoneIndex: Int?
    let numberValue: Int?
    /// 토큰 구조 스켈레톤 ("F-Z-N", "Z-N", "ZN", "F-ZN", "F-N")
    let skeleton: String

    /// 격자 인덱스로 쓸 수 있는 코드인지 (구역 또는 번호 최소 하나)
    var isGridUsable: Bool { zoneIndex != nil || numberValue != nil }
}

/// 기둥 코드 파서 — 토큰화 + 스켈레톤 유도 + 템플릿 매칭 (R4).
/// 번호판(12가3456)·안내문 등은 어떤 토큰 구조에도 해당하지 않아 nil 반환.
enum PillarCodeParser {

    /// 파싱 불가 코드로 등록된 세션의 스켈레톤 표식 — 되찾기는 원문 완전 일치만 사용 (FR-016)
    static let rawSkeleton = "RAW"

    private static let hangulZones = Array("가나다라마바사아자차카타파하")

    // MARK: - Parse

    /// 파싱 불가 코드(RAW 세션)의 원문 완전 일치 비교용 정규화
    static func normalized(_ text: String) -> String {
        normalize(text)
    }

    static func parse(_ text: String) -> ParsedCode? {
        let normalized = normalize(text)
        guard !normalized.isEmpty, normalized.count <= 12 else { return nil }

        let segments = normalized.split(separator: "-").map(String.init)
        guard !segments.isEmpty, segments.count <= 3 else { return nil }

        var floor: String?
        var zone: String?
        var number: Int?
        var kinds: [String] = []

        for (index, segment) in segments.enumerated() {
            if floor == nil, zone == nil, number == nil, let f = matchFloor(segment),
               segments.count > 1 || !isCombinedZN(segment) {
                // "B2"는 층/구역+번호 중의성 — 뒤에 다른 세그먼트가 있으면 층으로 해석
                floor = f
                kinds.append("F")
            } else if zone == nil, number == nil, let (z, n) = matchCombinedZN(segment) {
                zone = z
                number = n
                kinds.append("ZN")
            } else if zone == nil, number == nil, isZone(segment) {
                zone = segment
                kinds.append("Z")
            } else if number == nil, let n = Int(segment), (1...3).contains(segment.count) {
                number = n
                kinds.append("N")
            } else {
                _ = index
                return nil  // 분류 불가 세그먼트 포함 → 코드 아님 (번호판·안내문 기각 지점)
            }
        }

        guard zone != nil || number != nil else { return nil }

        return ParsedCode(
            raw: normalized,
            floorToken: floor,
            zoneToken: zone,
            zoneIndex: zone.flatMap(zoneIndex(of:)),
            numberValue: number,
            skeleton: kinds.joined(separator: "-")
        )
    }

    // MARK: - Template (FR-008)

    /// 등록 시 확보된 코드들에서 대표 스켈레톤 유도 (최빈값, 동률이면 토큰 수 많은 쪽)
    static func skeleton(fromRegistered codes: [ParsedCode]) -> String {
        guard !codes.isEmpty else { return rawSkeleton }
        var counts: [String: Int] = [:]
        for code in codes { counts[code.skeleton, default: 0] += 1 }
        return counts.max { lhs, rhs in
            (lhs.value, lhs.key.count) < (rhs.value, rhs.key.count)
        }?.key ?? rawSkeleton
    }

    /// 되찾기 후보 필터: 등록 스켈레톤과 구조 일치만 채택.
    /// 층 토큰은 주차장 내 위치에 따라 표기 생략이 있어 F 유무는 관대하게 본다.
    static func matchesTemplate(_ candidate: ParsedCode, skeleton: String) -> Bool {
        guard skeleton != rawSkeleton else { return false }
        if candidate.skeleton == skeleton { return true }
        return stripFloor(candidate.skeleton) == stripFloor(skeleton)
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        var s = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" ", "·", "/", "_", "—", "–", "."] {
            s = s.replacingOccurrences(of: separator, with: "-")
        }
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// "B2"·"지하2" → "B2"
    private static func matchFloor(_ segment: String) -> String? {
        if let match = segment.wholeMatch(of: /B(\d{1,2})/) { return "B\(match.1)" }
        if let match = segment.wholeMatch(of: /지하(\d{1,2})/) { return "B\(match.1)" }
        return nil
    }

    private static func isZone(_ segment: String) -> Bool {
        segment.wholeMatch(of: /[A-Z]{1,2}/) != nil
            || (segment.count == 1 && segment.unicodeScalars.first.map { ("가"..."힣").contains(String($0)) } == true)
    }

    private static func matchCombinedZN(_ segment: String) -> (String, Int)? {
        if let match = segment.wholeMatch(of: /([A-Z])(\d{1,3})/) {
            return (String(match.1), Int(match.2)!)
        }
        if let match = segment.wholeMatch(of: /([가-힣])(\d{1,3})/) {
            return (String(match.1), Int(match.2)!)
        }
        return nil
    }

    private static func isCombinedZN(_ segment: String) -> Bool {
        matchCombinedZN(segment) != nil
    }

    private static func zoneIndex(of zone: String) -> Int? {
        if zone.count == 1, let scalar = zone.unicodeScalars.first {
            if ("A"..."Z").contains(String(scalar)) {
                return Int(scalar.value - UnicodeScalar("A").value)
            }
            if let idx = hangulZones.firstIndex(of: Character(String(scalar))) {
                return idx
            }
        }
        // 2글자 영문 구역(AA…)은 초기 미지원 — 격자 인덱스 없이 원문 매칭만
        return nil
    }

    private static func stripFloor(_ skeleton: String) -> String {
        skeleton.hasPrefix("F-") ? String(skeleton.dropFirst(2)) : skeleton
    }
}
