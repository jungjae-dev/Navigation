import UIKit

/// Top banner showing next maneuver instruction, distance, and turn icon
final class ManeuverBannerView: UIView {

    // MARK: - UI Components

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        view.layer.cornerRadius = Theme.CornerRadius.medium
        view.layer.masksToBounds = true
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.image = UIImage(systemName: "arrow.up")
        return imageView
    }()

    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.maneuverDistance
        label.textColor = .white
        label.text = "--"
        return label
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.maneuverInstruction
        label.textColor = .white
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
        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(distanceLabel)
        containerView.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Spacing.lg),
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Theme.Spacing.lg),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            distanceLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Theme.Spacing.md),
            distanceLabel.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            distanceLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -Theme.Spacing.lg),

            instructionLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: Theme.Spacing.sm),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Spacing.lg),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Theme.Spacing.lg),
            instructionLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Theme.Spacing.lg),
        ])
    }

    // MARK: - Public

    func update(instruction: String, distance: String, iconName: String) {
        instructionLabel.text = instruction
        distanceLabel.text = distance
        iconImageView.image = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 36, weight: .bold))
    }
}
