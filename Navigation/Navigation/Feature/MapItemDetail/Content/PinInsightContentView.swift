import UIKit

/// 동네 인사이트 카드 목록 — 평평한 리스트(구분선) 스타일로 기존 상세 시트와 통일.
/// 카드가 많아도 detent 높이에 맞춰 스크롤되도록 UIScrollView로 감싼다.
final class PinInsightContentView: UIView {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let frameGuide = scrollView.frameLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),
        ])
    }

    /// 카드 목록으로 행 재구성 (행 사이 구분선)
    func configure(cards: [InsightCard]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, card) in cards.enumerated() {
            stack.addArrangedSubview(makeRow(for: card))
            if index < cards.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }
    }

    private func makeRow(for card: InsightCard) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: card.kind.symbolName))
        icon.tintColor = Theme.Colors.secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = card.kind.title
        titleLabel.font = Theme.Fonts.caption
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.Colors.secondaryLabel

        let valueLabel = UILabel()
        valueLabel.font = Theme.Fonts.callout
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.Colors.label
        valueLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.font = Theme.Fonts.caption
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = Theme.Colors.secondaryLabel
        detailLabel.numberOfLines = 0

        switch card.state {
        case .loading:
            valueLabel.text = "불러오는 중…"
            valueLabel.textColor = Theme.Colors.secondaryLabel
        case .failed:
            valueLabel.text = "정보 없음"
            valueLabel.textColor = Theme.Colors.secondaryLabel
        case .loaded(let content):
            valueLabel.text = content.headline
            valueLabel.textColor = Self.color(for: content.badge)
            var detail = content.detail ?? ""
            if let asOf = card.asOf, card.kind.isRealtime {
                let mins = max(0, Int(Date().timeIntervalSince(asOf) / 60))
                let timeText = mins < 1 ? "방금 기준" : "\(mins)분 전 기준"
                detail = detail.isEmpty ? timeText : "\(detail) · \(timeText)"
            }
            detailLabel.text = detail
        }

        let textStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        if !(detailLabel.text ?? "").isEmpty { textStack.addArrangedSubview(detailLabel) }
        textStack.axis = .vertical
        textStack.spacing = Theme.Spacing.xxs

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.spacing = Theme.Spacing.md
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(
            top: Theme.Spacing.md, leading: 0, bottom: Theme.Spacing.md, trailing: 0
        )
        return row
    }

    private func makeSeparator() -> UIView {
        let line = UIView()
        line.backgroundColor = Theme.Colors.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    private static func color(for badge: CardBadgeLevel?) -> UIColor {
        switch badge {
        case .good:    return Theme.Colors.success
        case .caution: return .systemOrange   // 주의색 — Theme 토큰 없음(의미색 유지)
        case .normal, .neutral, .none: return Theme.Colors.label
        }
    }
}
