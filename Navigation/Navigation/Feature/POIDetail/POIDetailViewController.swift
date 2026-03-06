import UIKit

final class POIDetailViewController: UIViewController {

    // MARK: - Callbacks

    var onRouteTapped: ((Place) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Properties

    private(set) var place: Place

    // MARK: - Constants

    static let titleBarHeight: CGFloat = 44

    // MARK: - UI Components

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "xmark.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        return button
    }()

    private let categoryImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Theme.Colors.primary
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.label
        label.numberOfLines = 2
        return label
    }()

    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.subheadline
        label.textColor = Theme.Colors.secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let phoneButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "phone.fill")
        config.imagePadding = Theme.Spacing.sm
        config.contentInsets = .init(top: Theme.Spacing.sm, leading: 0, bottom: Theme.Spacing.sm, trailing: 0)
        button.configuration = config
        return button
    }()

    private let websiteButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "safari.fill")
        config.imagePadding = Theme.Spacing.sm
        config.contentInsets = .init(top: Theme.Spacing.sm, leading: 0, bottom: Theme.Spacing.sm, trailing: 0)
        button.configuration = config
        return button
    }()

    private let routeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "경로"
        config.image = UIImage(systemName: "arrow.triangle.turn.up.right.diamond.fill")
        config.imagePadding = Theme.Spacing.sm
        config.cornerStyle = .medium
        config.baseBackgroundColor = Theme.Colors.primary
        config.baseForegroundColor = .white
        button.configuration = config
        return button
    }()

    // MARK: - Init

    init(place: Place) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configure()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        let headerStack = UIStackView(arrangedSubviews: [categoryImageView, nameLabel])
        headerStack.axis = .horizontal
        headerStack.spacing = Theme.Spacing.md
        headerStack.alignment = .center

        NSLayoutConstraint.activate([
            categoryImageView.widthAnchor.constraint(equalToConstant: 32),
            categoryImageView.heightAnchor.constraint(equalToConstant: 32),
        ])

        let infoStack = UIStackView(arrangedSubviews: [headerStack, addressLabel])
        infoStack.axis = .vertical
        infoStack.spacing = Theme.Spacing.xs

        let contactStack = UIStackView(arrangedSubviews: [phoneButton, websiteButton])
        contactStack.axis = .vertical
        contactStack.spacing = 0

        let mainStack = UIStackView(arrangedSubviews: [infoStack, contactStack, routeButton])
        mainStack.axis = .vertical
        mainStack.spacing = Theme.Spacing.lg
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(closeButton)
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            closeButton.centerYAnchor.constraint(equalTo: view.topAnchor, constant: Self.titleBarHeight / 2),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.titleBarHeight),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            routeButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        phoneButton.addTarget(self, action: #selector(phoneTapped), for: .touchUpInside)
        websiteButton.addTarget(self, action: #selector(websiteTapped), for: .touchUpInside)
        routeButton.addTarget(self, action: #selector(routeTapped), for: .touchUpInside)
    }

    // MARK: - Public

    func update(with place: Place) {
        self.place = place
        configure()
    }

    // MARK: - Configure

    private func configure() {
        nameLabel.text = place.name ?? "알 수 없는 장소"
        addressLabel.text = place.address

        let iconName = iconName(for: place.category)
        categoryImageView.image = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium))

        if let phone = place.phoneNumber {
            phoneButton.isHidden = false
            phoneButton.configuration?.title = phone
        } else {
            phoneButton.isHidden = true
        }

        if let url = place.url {
            websiteButton.isHidden = false
            websiteButton.configuration?.title = url.host ?? url.absoluteString
        } else {
            websiteButton.isHidden = true
        }

        addressLabel.isHidden = (addressLabel.text == nil)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func phoneTapped() {
        guard let phone = place.phoneNumber,
              let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func websiteTapped() {
        guard let url = place.url else { return }
        UIApplication.shared.open(url)
    }

    @objc private func routeTapped() {
        onRouteTapped?(place)
    }

    // MARK: - Helpers

    private func iconName(for category: String?) -> String {
        guard let category else { return "mappin.circle.fill" }
        let lower = category.lowercased()
        if lower.contains("restaurant") || lower.contains("음식") { return "fork.knife" }
        if lower.contains("cafe") || lower.contains("카페") { return "cup.and.saucer.fill" }
        if lower.contains("gas") || lower.contains("주유") { return "fuelpump.fill" }
        if lower.contains("hospital") || lower.contains("병원") { return "cross.case.fill" }
        if lower.contains("pharmacy") || lower.contains("약국") { return "pills.fill" }
        if lower.contains("school") || lower.contains("학교") { return "graduationcap.fill" }
        if lower.contains("store") || lower.contains("마트") { return "bag.fill" }
        if lower.contains("parking") || lower.contains("주차") { return "p.circle.fill" }
        if lower.contains("bank") || lower.contains("은행") { return "banknote.fill" }
        if lower.contains("hotel") || lower.contains("숙박") { return "bed.double.fill" }
        if lower.contains("park") || lower.contains("공원") { return "leaf.fill" }
        return "mappin.circle.fill"
    }
}
