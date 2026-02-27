import UIKit
import MapKit

final class POIDetailViewController: UIViewController {

    // MARK: - Callbacks

    var onRouteTapped: ((MKMapItem) -> Void)?

    // MARK: - Properties

    private(set) var mapItem: MKMapItem

    // MARK: - UI Components

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

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
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

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Spacing.xl),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            routeButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        phoneButton.addTarget(self, action: #selector(phoneTapped), for: .touchUpInside)
        websiteButton.addTarget(self, action: #selector(websiteTapped), for: .touchUpInside)
        routeButton.addTarget(self, action: #selector(routeTapped), for: .touchUpInside)
    }

    // MARK: - Public

    func update(with mapItem: MKMapItem) {
        self.mapItem = mapItem
        configure()
    }

    // MARK: - Configure

    private func configure() {
        nameLabel.text = mapItem.name ?? "알 수 없는 장소"
        addressLabel.text = mapItem.address?.fullAddress ?? mapItem.address?.shortAddress

        let iconName = iconName(for: mapItem.pointOfInterestCategory)
        categoryImageView.image = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium))

        if let phone = mapItem.phoneNumber {
            phoneButton.isHidden = false
            phoneButton.configuration?.title = phone
        } else {
            phoneButton.isHidden = true
        }

        if let url = mapItem.url {
            websiteButton.isHidden = false
            websiteButton.configuration?.title = url.host ?? url.absoluteString
        } else {
            websiteButton.isHidden = true
        }

        addressLabel.isHidden = (addressLabel.text == nil)
    }

    // MARK: - Actions

    @objc private func phoneTapped() {
        guard let phone = mapItem.phoneNumber,
              let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func websiteTapped() {
        guard let url = mapItem.url else { return }
        UIApplication.shared.open(url)
    }

    @objc private func routeTapped() {
        onRouteTapped?(mapItem)
    }

    // MARK: - Helpers

    private func iconName(for category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "mappin.circle.fill" }
        return switch category {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .gasStation: "fuelpump.fill"
        case .hospital: "cross.case.fill"
        case .pharmacy: "pills.fill"
        case .school, .university: "graduationcap.fill"
        case .store: "bag.fill"
        case .parking: "p.circle.fill"
        case .bank, .atm: "banknote.fill"
        case .hotel: "bed.double.fill"
        case .park: "leaf.fill"
        case .museum: "building.columns.fill"
        case .theater, .movieTheater: "theatermasks.fill"
        case .airport: "airplane"
        case .publicTransport: "bus.fill"
        case .fitnessCenter: "figure.run"
        case .laundry: "washer.fill"
        case .postOffice: "envelope.fill"
        case .library: "books.vertical.fill"
        default: "mappin.circle.fill"
        }
    }
}
