import UIKit
import SafariServices

/// POI(Place) 상세 컨텐츠 — 주소, 거리, 전화, 상세보기, 즐겨찾기
final class PlaceContentView: UIView {

    // MARK: - Callbacks

    var onFavoriteToggled: (() -> Void)?

    // MARK: - UI

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

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

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
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])

        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        phoneButton.addTarget(self, action: #selector(phoneTapped), for: .touchUpInside)
        detailButton.addTarget(self, action: #selector(detailTapped), for: .touchUpInside)
    }

    // MARK: - Public

    func configure(with place: Place, isFavorite: Bool) {
        favoriteButton.setFavoriteState(isFavorite)

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

        currentPlace = place
    }

    // MARK: - Internal state for action handlers

    private var currentPlace: Place?

    @objc private func favoriteTapped() {
        onFavoriteToggled?()
    }

    @objc private func phoneTapped() {
        guard let phone = currentPlace?.phoneNumber,
              let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func detailTapped() {
        guard let url = currentPlace?.url else { return }
        let safariVC = SFSafariViewController(url: url)
        // 부모 VC 통해 present
        if let parentVC = parentViewController {
            parentVC.present(safariVC, animated: true)
        }
    }
}

// MARK: - Helper

private extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}
