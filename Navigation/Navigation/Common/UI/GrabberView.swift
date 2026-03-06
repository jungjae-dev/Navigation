import UIKit

final class GrabberView: UIView {

    private let bar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.separator
        view.layer.cornerRadius = 2.5
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(bar)

        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.widthAnchor.constraint(equalToConstant: 36),
            bar.heightAnchor.constraint(equalToConstant: 5),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 20)
    }
}
