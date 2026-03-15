import UIKit
import SafariServices
import CoreLocation

final class POIDetailViewController: UIViewController {

    // MARK: - Callbacks

    var onRouteTapped: ((Place) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Properties

    private(set) var place: Place
    private let dataService: DataService

    // MARK: - UI Components

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

    private let favoriteButton = DrawerIconButton(preset: .favorite)

    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.subheadline
        label.textColor = Theme.Colors.secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.caption
        label.textColor = Theme.Colors.secondaryLabel
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

    private let detailButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "info.circle.fill")
        config.imagePadding = Theme.Spacing.sm
        config.title = "상세보기"
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

    init(place: Place, dataService: DataService = .shared) {
        self.place = place
        self.dataService = dataService
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

        // Address row: address label + favorite icon
        let addressRow = UIStackView(arrangedSubviews: [favoriteButton, addressLabel])
        addressRow.axis = .horizontal
        addressRow.alignment = .center
        addressRow.spacing = Theme.Spacing.sm

        favoriteButton.setContentHuggingPriority(.required, for: .horizontal)
        favoriteButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let contactStack = UIStackView(arrangedSubviews: [phoneButton, detailButton])
        contactStack.axis = .vertical
        contactStack.spacing = 0

        let contentStack = UIStackView(arrangedSubviews: [addressRow, distanceLabel, contactStack])
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
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        phoneButton.addTarget(self, action: #selector(phoneTapped), for: .touchUpInside)
        detailButton.addTarget(self, action: #selector(detailTapped), for: .touchUpInside)
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

        // Favorite state
        updateFavoriteButton()

        addressLabel.text = place.address
        addressLabel.isHidden = (place.address == nil)

        if let doc = place.providerRawData as? KakaoSearchResponse.Document,
           let distStr = doc.distance,
           let meters = Double(distStr) {
            if meters >= 1000 {
                distanceLabel.text = String(format: "%.1fkm", meters / 1000)
            } else {
                distanceLabel.text = "\(Int(meters))m"
            }
            distanceLabel.isHidden = false
        } else {
            distanceLabel.isHidden = true
        }

        if let phone = place.phoneNumber {
            phoneButton.isHidden = false
            phoneButton.configuration?.title = phone
        } else {
            phoneButton.isHidden = true
        }

        detailButton.isHidden = (place.url == nil)
    }

    private func updateFavoriteButton() {
        let isFav = dataService.isFavorite(
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude
        )
        favoriteButton.setFavoriteState(isFav)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func favoriteTapped() {
        let coord = place.coordinate
        if dataService.isFavorite(latitude: coord.latitude, longitude: coord.longitude) {
            if let existing = dataService.findFavorite(latitude: coord.latitude, longitude: coord.longitude) {
                dataService.deleteFavorite(existing)
            }
        } else {
            let name = place.name ?? "즐겨찾기"
            let address = place.address ?? ""
            dataService.saveFavoriteFromCoordinate(
                name: name,
                address: address,
                latitude: coord.latitude,
                longitude: coord.longitude
            )
        }
        updateFavoriteButton()
    }

    @objc private func phoneTapped() {
        guard let phone = place.phoneNumber,
              let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func detailTapped() {
        guard let url = place.url else { return }
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
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
