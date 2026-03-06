import Foundation

struct SearchCompletion: Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let highlightRanges: [NSRange]?

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        highlightRanges: [NSRange]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.highlightRanges = highlightRanges
    }
}
