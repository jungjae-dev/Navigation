import UIKit

final class DrawerContainerView: UIView {

    private(set) var initialTouchPoint: CGPoint?

    let grabber = GrabberView()
    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = Theme.Colors.background
        layer.cornerRadius = Theme.CornerRadius.large
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.shadowColor = Theme.Shadow.color
        layer.shadowOpacity = Theme.Shadow.opacity
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = Theme.Shadow.radius
        clipsToBounds = false

        grabber.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabber)
        addSubview(contentView)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: topAnchor),
            grabber.leadingAnchor.constraint(equalTo: leadingAnchor),
            grabber.trailingAnchor.constraint(equalTo: trailingAnchor),

            contentView.topAnchor.constraint(equalTo: grabber.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        initialTouchPoint = touches.first?.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        initialTouchPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        initialTouchPoint = nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
