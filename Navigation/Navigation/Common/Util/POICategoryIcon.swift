import Foundation

enum POICategoryIcon {

    static func iconName(for category: String?) -> String {
        guard let category else { return "mappin.circle.fill" }
        let lower = category.lowercased()
        if lower.contains("restaurant") || lower.contains("음식") { return "fork.knife" }
        if lower.contains("cafe") || lower.contains("카페") { return "cup.and.saucer.fill" }
        if lower.contains("gas") || lower.contains("주유") { return "fuelpump.fill" }
        if lower.contains("hospital") || lower.contains("병원") { return "cross.case.fill" }
        if lower.contains("pharmacy") || lower.contains("약국") { return "pills.fill" }
        if lower.contains("school") || lower.contains("학교") { return "graduationcap.fill" }
        if lower.contains("store") || lower.contains("마트") { return "bag.fill" }
        if lower.contains("parking") || lower.contains("주차") { return "p.circle.fill" }
        if lower.contains("bank") || lower.contains("은행") { return "banknote.fill" }
        if lower.contains("hotel") || lower.contains("숙박") { return "bed.double.fill" }
        if lower.contains("park") || lower.contains("공원") { return "leaf.fill" }
        return "mappin.circle.fill"
    }
}
