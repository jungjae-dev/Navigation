import UIKit
import MapKit

final class MapControlButtonsView: UIView {

    // MARK: - Callbacks

    var onCurrentLocationTapped: (() -> Void)?
    var onMapModeTapped: (() -> Void)?

    // MARK: - UI

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.spacing = Theme.Spacing.sm
        return sv
    }()

    private let currentLocationButton = UIButton(type: .system)
    private let mapModeButton = UIButton(type: .system)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        setupActions()
        setupAccessibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        addSubview(stackView)

        configureButton(currentLocationButton, iconName: "location")
        stackView.addArrangedSubview(currentLocationButton)

        configureButton(mapModeButton, iconName: "map")
        stackView.addArrangedSubview(mapModeButton)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureButton(_ button: UIButton, iconName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        button.backgroundColor = Theme.Colors.secondaryBackground
        button.layer.cornerRadius = 24
        button.layer.shadowColor = Theme.Shadow.color
        button.layer.shadowOpacity = Theme.Shadow.opacity
        button.layer.shadowOffset = Theme.Shadow.offset
        button.layer.shadowRadius = Theme.Shadow.radius

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func setupActions() {
        currentLocationButton.addTarget(self, action: #selector(currentLocationTapped), for: .touchUpInside)
        mapModeButton.addTarget(self, action: #selector(mapModeTapped), for: .touchUpInside)
    }

    private func setupAccessibility() {
        currentLocationButton.accessibilityLabel = "현재 위치"
        currentLocationButton.accessibilityHint = "현재 위치로 이동합니다"

        mapModeButton.accessibilityLabel = "지도 모드"
        mapModeButton.accessibilityHint = "지도 표시 유형을 변경합니다"
    }

    // MARK: - Actions

    @objc private func currentLocationTapped() {
        onCurrentLocationTapped?()
    }

    @objc private func mapModeTapped() {
        onMapModeTapped?()
    }

    // MARK: - State Updates

    func updateCurrentLocationIcon(for mode: MKUserTrackingMode) {
        let iconName: String
        let tintColor: UIColor

        switch mode {
        case .none:
            iconName = "location"
            tintColor = Theme.Colors.secondaryLabel
        case .follow:
            iconName = "location.fill"
            tintColor = Theme.Colors.primary
        case .followWithHeading:
            iconName = "location.north.line.fill"
            tintColor = Theme.Colors.primary
        @unknown default:
            iconName = "location"
            tintColor = Theme.Colors.secondaryLabel
        }

        currentLocationButton.setImage(
            UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        currentLocationButton.tintColor = tintColor
    }

    func updateMapModeIcon(isSatellite: Bool) {
        let iconName = isSatellite ? "globe.americas.fill" : "map"

        mapModeButton.setImage(
            UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
    }
}
