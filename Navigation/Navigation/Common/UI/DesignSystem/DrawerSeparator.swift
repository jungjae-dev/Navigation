import UIKit

final class DrawerSeparator: UIView {

    enum Style {
        case fullWidth
        case inset
    }

    private let style: Style

    init(style: Style = .fullWidth) {
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Theme.Drawer.Separator.color
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 1 / UITraitCollection.current.displayScale)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard let superview else { return }

        let inset: CGFloat = style == .inset ? Theme.Drawer.Separator.horizontalInset : 0

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: intrinsicContentSize.height),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -inset),
        ])
    }
}
