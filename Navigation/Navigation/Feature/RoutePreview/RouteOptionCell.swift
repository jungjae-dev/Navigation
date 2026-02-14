import UIKit
import MapKit

final class RouteOptionCell: UITableViewCell {

    // MARK: - UI Components

    private let transportIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(systemName: "car.fill")
        return imageView
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        return label
    }()

    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.subheadline
        label.textColor = Theme.Colors.secondaryLabel
        return label
    }()

    private let arrivalLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.footnote
        label.textColor = Theme.Colors.secondaryLabel
        return label
    }()

    private let checkmark: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.contentMode = .scaleAspectFit
        return imageView
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
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(transportIcon)
        contentView.addSubview(timeLabel)
        contentView.addSubview(distanceLabel)
        contentView.addSubview(arrivalLabel)
        contentView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            transportIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.lg),
            transportIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            transportIcon.widthAnchor.constraint(equalToConstant: 24),
            transportIcon.heightAnchor.constraint(equalToConstant: 24),

            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Spacing.md),
            timeLabel.leadingAnchor.constraint(equalTo: transportIcon.trailingAnchor, constant: Theme.Spacing.md),

            distanceLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: Theme.Spacing.sm),
            distanceLabel.lastBaselineAnchor.constraint(equalTo: timeLabel.lastBaselineAnchor),

            arrivalLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: Theme.Spacing.xs),
            arrivalLabel.leadingAnchor.constraint(equalTo: timeLabel.leadingAnchor),
            arrivalLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.md),

            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.lg),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    // MARK: - Configure

    func configure(with route: MKRoute, isSelected: Bool) {
        timeLabel.text = route.formattedTravelTime
        distanceLabel.text = route.formattedDistance
        arrivalLabel.text = route.formattedArrivalTime

        let color = isSelected ? Theme.Colors.primary : Theme.Colors.secondaryLabel
        transportIcon.tintColor = color
        timeLabel.textColor = isSelected ? Theme.Colors.primary : Theme.Colors.label
        checkmark.isHidden = !isSelected
        checkmark.tintColor = Theme.Colors.primary
    }
}
