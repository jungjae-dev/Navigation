import UIKit

final class FavoriteCell: UICollectionViewCell {

    static let reuseIdentifier = "FavoriteCell"

    // MARK: - UI

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.secondaryBackground
        view.layer.cornerRadius = Theme.CornerRadius.medium
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Theme.Colors.primary
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.footnote
        label.textColor = Theme.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 1
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
        contentView.addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Theme.Spacing.sm),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: Theme.Spacing.xs),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Spacing.xs),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Theme.Spacing.xs),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Theme.Spacing.xs),
        ])
    }

    // MARK: - Configure

    func configure(with favorite: FavoritePlace) {
        nameLabel.text = favorite.name
        iconImageView.image = UIImage(systemName: iconName(for: favorite.category))?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
    }

    private func iconName(for category: String) -> String {
        switch category {
        case "home": return "house.fill"
        case "work": return "building.2.fill"
        case "cafe": return "cup.and.saucer.fill"
        case "gym": return "dumbbell.fill"
        case "school": return "graduationcap.fill"
        default: return "star.fill"
        }
    }
}
