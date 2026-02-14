import UIKit

/// Bottom bar showing ETA, remaining distance/time, and end navigation button
final class NavigationBottomBar: UIView {

    // MARK: - UI Components

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.background
        view.layer.cornerRadius = Theme.CornerRadius.large
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = Theme.Shadow.radius
        return view
    }()

    private let etaLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.eta
        label.textColor = Theme.Colors.primary
        label.text = "--:--"
        return label
    }()

    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.body
        label.textColor = Theme.Colors.label
        label.text = "-- km"
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.body
        label.textColor = Theme.Colors.secondaryLabel
        label.text = "-- 분"
        return label
    }()

    private let endButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("안내 종료", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = Theme.Fonts.headline
        button.backgroundColor = Theme.Colors.destructive
        button.layer.cornerRadius = Theme.CornerRadius.small
        return button
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.separator
        return view
    }()

    // MARK: - Callback

    var onEndNavigation: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(etaLabel)
        containerView.addSubview(separatorView)
        containerView.addSubview(distanceLabel)
        containerView.addSubview(timeLabel)
        containerView.addSubview(endButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            etaLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Theme.Spacing.lg),
            etaLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Spacing.xl),

            separatorView.leadingAnchor.constraint(equalTo: etaLabel.trailingAnchor, constant: Theme.Spacing.md),
            separatorView.centerYAnchor.constraint(equalTo: etaLabel.centerYAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 20),

            distanceLabel.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: Theme.Spacing.md),
            distanceLabel.centerYAnchor.constraint(equalTo: etaLabel.centerYAnchor),

            timeLabel.leadingAnchor.constraint(equalTo: distanceLabel.trailingAnchor, constant: Theme.Spacing.md),
            timeLabel.centerYAnchor.constraint(equalTo: etaLabel.centerYAnchor),

            endButton.topAnchor.constraint(equalTo: etaLabel.bottomAnchor, constant: Theme.Spacing.md),
            endButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Theme.Spacing.xl),
            endButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Theme.Spacing.xl),
            endButton.heightAnchor.constraint(equalToConstant: 44),
            endButton.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.md),
        ])
    }

    private func setupActions() {
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)
    }

    // MARK: - Public

    func update(eta: String, distance: String, time: String) {
        etaLabel.text = eta
        distanceLabel.text = distance
        timeLabel.text = time
    }

    // MARK: - Actions

    @objc private func endTapped() {
        onEndNavigation?()
    }
}
