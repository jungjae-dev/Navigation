import UIKit

final class DrawerSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "DrawerSectionHeader"

    // MARK: - UI Components

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Theme.Drawer.SectionHeader.iconColor
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Drawer.SectionHeader.titleFont
        label.textColor = Theme.Drawer.SectionHeader.titleColor
        return label
    }()

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
        addSubview(iconImageView)
        addSubview(titleLabel)

        let iconSize = Theme.Drawer.SectionHeader.iconSize
        let padding = Theme.Drawer.SectionHeader.horizontalPadding

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.leadingAnchor.constraint(
                equalTo: iconImageView.trailingAnchor,
                constant: Theme.Drawer.SectionHeader.iconToTitleSpacing
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),
        ])
    }

    // MARK: - Configure

    func configure(title: String, iconName: String?, iconColor: UIColor? = nil) {
        titleLabel.text = title

        if let iconName {
            iconImageView.isHidden = false
            iconImageView.image = UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            iconImageView.tintColor = iconColor ?? Theme.Drawer.SectionHeader.iconColor
        } else {
            iconImageView.isHidden = true
        }
    }
}
