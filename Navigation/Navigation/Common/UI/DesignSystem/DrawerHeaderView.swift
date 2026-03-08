import UIKit

final class DrawerHeaderView: UIView {

    // MARK: - UI Components

    private let leftArea: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.md
        return stack
    }()

    private let centerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let rightArea: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xs
        return stack
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Drawer.Header.titleFont
        label.textColor = Theme.Drawer.Header.titleColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let leftIconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Theme.Colors.primary
        return iv
    }()

    let separator = DrawerSeparator(style: .fullWidth)

    private var leftIconSizeConstraints: [NSLayoutConstraint] = []
    private var centerLeadingToLeftArea: NSLayoutConstraint!
    private var centerLeadingToSuperview: NSLayoutConstraint!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftArea)
        addSubview(centerContainer)
        addSubview(rightArea)
        addSubview(separator)

        let padding = Theme.Drawer.Header.padding
        let height = Theme.Drawer.Header.height

        centerLeadingToLeftArea = centerContainer.leadingAnchor.constraint(equalTo: leftArea.trailingAnchor, constant: Theme.Spacing.sm)
        centerLeadingToSuperview = centerContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),

            leftArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            leftArea.centerYAnchor.constraint(equalTo: centerYAnchor),

            centerContainer.trailingAnchor.constraint(equalTo: rightArea.leadingAnchor, constant: -Theme.Spacing.sm),
            centerContainer.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightArea.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            rightArea.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateCenterLeading(leftVisible: false)
    }

    private func updateCenterLeading(leftVisible: Bool) {
        leftArea.isHidden = !leftVisible
        // Deactivate first to avoid simultaneous constraint conflict
        centerLeadingToLeftArea.isActive = false
        centerLeadingToSuperview.isActive = false
        centerLeadingToLeftArea.isActive = leftVisible
        centerLeadingToSuperview.isActive = !leftVisible
    }

    // MARK: - Public API

    func setTitle(_ text: String, alignment: NSTextAlignment = .natural) {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }

        titleLabel.text = text
        titleLabel.textAlignment = alignment
        centerContainer.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
        ])
    }

    func setCenterView(_ view: UIView) {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }

        view.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
        ])
    }

    func setLeftIcon(_ image: UIImage?, size: CGFloat = Theme.Drawer.Cell.iconSize) {
        updateCenterLeading(leftVisible: image != nil)
        leftIconView.image = image

        NSLayoutConstraint.deactivate(leftIconSizeConstraints)
        leftIconSizeConstraints = [
            leftIconView.widthAnchor.constraint(equalToConstant: size),
            leftIconView.heightAnchor.constraint(equalToConstant: size),
        ]
        NSLayoutConstraint.activate(leftIconSizeConstraints)

        if leftIconView.superview == nil {
            leftArea.addArrangedSubview(leftIconView)
        }
    }

    func addLeftAction(_ button: UIButton) {
        leftArea.addArrangedSubview(button)
        updateCenterLeading(leftVisible: true)
    }

    func addRightAction(_ button: UIButton) {
        rightArea.addArrangedSubview(button)
    }
}
