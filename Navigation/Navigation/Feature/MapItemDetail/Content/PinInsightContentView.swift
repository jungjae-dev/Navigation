import UIKit

/// 동네 인사이트 카드 목록 표시 뷰.
/// (슬라이스 1: 시스템 색상 사용 — 디자인 토큰화는 폴리시 T031에서)
final class PinInsightContentView: UIView {

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    /// 카드 목록으로 행 재구성
    func configure(cards: [InsightCard]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for card in cards {
            stack.addArrangedSubview(makeRow(for: card))
        }
    }

    private func makeRow(for card: InsightCard) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12

        let icon = UIImageView(image: UIImage(systemName: card.kind.symbolName))
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = card.kind.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .tertiaryLabel
        detailLabel.numberOfLines = 0

        switch card.state {
        case .loading:
            valueLabel.text = "불러오는 중…"
            valueLabel.textColor = .secondaryLabel
        case .failed:
            valueLabel.text = "정보 없음"
            valueLabel.textColor = .secondaryLabel
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
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        return container
    }

    private static func color(for badge: CardBadgeLevel?) -> UIColor {
        switch badge {
        case .good:    return .systemGreen
        case .normal:  return .label
        case .caution: return .systemOrange
        case .neutral, .none: return .label
        }
    }
}
