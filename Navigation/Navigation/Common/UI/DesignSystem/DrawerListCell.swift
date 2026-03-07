import UIKit

final class DrawerListCell: UICollectionViewCell {

    static let reuseIdentifier = "DrawerListCell"

    // MARK: - UI Components

    private let iconContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Drawer.Cell.iconBackgroundColor
        view.layer.cornerRadius = Theme.Drawer.Cell.iconCornerRadius
        return view
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Theme.Drawer.Cell.iconColor
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Drawer.Cell.titleFont
        label.textColor = Theme.Drawer.Cell.titleColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Drawer.Cell.subtitleFont
        label.textColor = Theme.Drawer.Cell.subtitleColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xxs
        return stack
    }()

    private let accessoryContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cellSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Drawer.Separator.color
        return view
    }()

    var showsSeparator: Bool = true {
        didSet { cellSeparator.isHidden = !showsSeparator }
    }

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
        let iconSize = Theme.Drawer.Cell.iconSize
        let padding = Theme.Drawer.Cell.horizontalPadding
        let iconSpacing = Theme.Drawer.Cell.iconToTextSpacing

        iconContainer.addSubview(iconImageView)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        contentView.addSubview(iconContainer)
        contentView.addSubview(textStack)
        contentView.addSubview(accessoryContainer)
        contentView.addSubview(cellSeparator)

        let iconInset = (iconSize - 20) / 2

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: iconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: iconSize),

            iconImageView.topAnchor.constraint(equalTo: iconContainer.topAnchor, constant: iconInset),
            iconImageView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor, constant: iconInset),
            iconImageView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: -iconInset),
            iconImageView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: -iconInset),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: iconSpacing),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor, constant: -Theme.Spacing.sm),

            accessoryContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            accessoryContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            cellSeparator.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            cellSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cellSeparator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            cellSeparator.heightAnchor.constraint(equalToConstant: 1 / UITraitCollection.current.displayScale),
        ])
    }

    // MARK: - Configure

    func configure(
        title: String,
        subtitle: String? = nil,
        iconImage: UIImage? = nil,
        iconBackgroundColor: UIColor? = nil,
        accessoryView: UIView? = nil
    ) {
        titleLabel.text = title

        if let subtitle, !subtitle.isEmpty {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }

        iconImageView.image = iconImage
        if let iconBackgroundColor {
            iconContainer.backgroundColor = iconBackgroundColor
        }

        accessoryContainer.subviews.forEach { $0.removeFromSuperview() }
        if let accessoryView {
            accessoryView.translatesAutoresizingMaskIntoConstraints = false
            accessoryContainer.addSubview(accessoryView)
            NSLayoutConstraint.activate([
                accessoryView.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
                accessoryView.bottomAnchor.constraint(equalTo: accessoryContainer.bottomAnchor),
                accessoryView.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
                accessoryView.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor),
            ])
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        contentView.backgroundColor = highlighted
            ? Theme.Colors.secondaryBackground
            : .clear
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = true
        iconImageView.image = nil
        iconContainer.backgroundColor = Theme.Drawer.Cell.iconBackgroundColor
        accessoryContainer.subviews.forEach { $0.removeFromSuperview() }
        contentView.backgroundColor = .clear
        showsSeparator = true
    }
}
