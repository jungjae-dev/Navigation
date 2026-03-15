import UIKit

final class POIDetailViewController: UIViewController {

    // MARK: - Callbacks

    var onRouteTapped: ((Place) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Properties

    private(set) var place: Place

    // MARK: - UI Components

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

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

    private let routeButton = DrawerActionButton(
        style: .primary,
        title: "경로",
        iconName: "arrow.triangle.turn.up.right.diamond.fill"
    )

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

        // Header: category icon + place name + close
        headerView.addRightAction(closeButton)

        let contactStack = UIStackView(arrangedSubviews: [phoneButton, websiteButton])
        contactStack.axis = .vertical
        contactStack.spacing = 0

        let contentStack = UIStackView(arrangedSubviews: [addressLabel, contactStack])
        contentStack.axis = .vertical
        contentStack.spacing = Theme.Spacing.lg
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerView)
        view.addSubview(contentStack)

        let padding = Theme.Drawer.Layout.contentHorizontalPadding

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(
                equalTo: headerView.bottomAnchor,
                constant: Theme.Drawer.Layout.contentTopPadding
            ),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
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
        let placeName = place.name ?? "알 수 없는 장소"
        let iconName = POICategoryIcon.iconName(for: place.category)
        let categoryIcon = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.IconSize.lg, weight: .medium))

        headerView.setLeftIcon(categoryIcon, size: Theme.Drawer.Cell.iconSize)
        headerView.setTitle(placeName)

        addressLabel.text = place.address
        addressLabel.isHidden = (place.address == nil)

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
}

// MARK: - DrawerFooterProviding

extension POIDetailViewController: DrawerFooterProviding {

    var footerContentView: UIView {
        let container = UIView()
        container.backgroundColor = Theme.Colors.background

        routeButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(routeButton)

        let padding = Theme.Drawer.Layout.contentHorizontalPadding

        NSLayoutConstraint.activate([
            routeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.md),
            routeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            routeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            routeButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.md),
        ])

        return container
    }
}
