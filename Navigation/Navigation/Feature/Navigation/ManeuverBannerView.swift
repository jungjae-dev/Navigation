import UIKit

/// Top banner showing next maneuver instruction, distance, and turn icon
final class ManeuverBannerView: UIView {

    // MARK: - UI Components

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Banner.backgroundColor
        view.layer.cornerRadius = Theme.Banner.cornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Theme.Banner.foregroundColor
        imageView.image = UIImage(systemName: "arrow.up")
        return imageView
    }()

    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Banner.distanceFont
        label.textColor = Theme.Banner.foregroundColor
        label.text = "--"
        return label
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Banner.instructionFont
        label.textColor = Theme.Banner.foregroundColor
        label.numberOfLines = 2
        label.text = "경로를 따라 이동하세요"
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
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently

        iconImageView.isAccessibilityElement = false
        distanceLabel.isAccessibilityElement = false
        instructionLabel.isAccessibilityElement = false

        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(distanceLabel)
        containerView.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Banner.padding),
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Theme.Banner.padding),
            iconImageView.widthAnchor.constraint(equalToConstant: Theme.Banner.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Theme.Banner.iconSize),

            distanceLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Theme.Spacing.md),
            distanceLabel.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            distanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -Theme.Banner.padding),

            instructionLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: Theme.Spacing.sm),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Banner.padding),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Theme.Banner.padding),
            instructionLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Theme.Banner.padding),
        ])
    }

    // MARK: - Public

    func update(instruction: String, distance: String, iconName: String) {
        instructionLabel.text = instruction
        distanceLabel.text = distance
        iconImageView.image = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.Banner.iconSize, weight: .bold))

        accessibilityLabel = "\(distance) 후 \(instruction)"
    }
}
