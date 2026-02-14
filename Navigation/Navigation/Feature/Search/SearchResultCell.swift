import UIKit
import MapKit

final class SearchResultCell: UITableViewCell {

    // MARK: - UI Components

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Theme.Colors.primary
        imageView.image = UIImage(systemName: "mappin.circle.fill")
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.label
        return label
    }()

    private let addressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.subheadline
        label.textColor = Theme.Colors.secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(addressLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.lg),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Spacing.md),
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Theme.Spacing.md),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.lg),

            addressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Theme.Spacing.xs),
            addressLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            addressLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.md),
        ])
    }

    // MARK: - Configure

    func configure(with mapItem: MKMapItem, isHighlighted: Bool) {
        nameLabel.text = mapItem.name
        addressLabel.text = mapItem.address?.shortAddress ?? mapItem.address?.fullAddress
        backgroundColor = isHighlighted ? Theme.Colors.secondaryBackground : Theme.Colors.background
        iconImageView.tintColor = isHighlighted ? Theme.Colors.primary : Theme.Colors.secondaryLabel
    }
}
