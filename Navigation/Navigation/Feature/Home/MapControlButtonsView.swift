import UIKit
import MapKit

final class MapControlButtonsView: UIView {

    // MARK: - Callbacks

    var onCurrentLocationTapped: (() -> Void)?
    var onMapModeTapped: (() -> Void)?
    var onBikeLayerTapped: (() -> Void)?
    var onBikeRefreshTapped: (() -> Void)?

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
    private let bikeLayerButton = UIButton(type: .system)
    private let bikeRefreshButton = UIButton(type: .system)

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

        configureButton(bikeLayerButton, iconName: "bicycle")
        // bicycle 아이콘은 다른 SF Symbol 보다 시각적으로 크게 보여서 살짝 줄이고, weight 는 두껍게
        bikeLayerButton.setImage(
            UIImage(systemName: "bicycle")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize - 4, weight: .bold)),
            for: .normal
        )
        stackView.addArrangedSubview(bikeLayerButton)

        // 새로고침 버튼 — 자전거 ON 일 때만 노출. stackView 바깥에서 bike 버튼 좌측에 별도 배치
        configureButton(bikeRefreshButton, iconName: "arrow.clockwise")
        bikeRefreshButton.isHidden = true
        addSubview(bikeRefreshButton)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // refresh 는 자전거 버튼의 좌측에 배치
            bikeRefreshButton.trailingAnchor.constraint(equalTo: bikeLayerButton.leadingAnchor, constant: -Theme.Spacing.sm),
            bikeRefreshButton.centerYAnchor.constraint(equalTo: bikeLayerButton.centerYAnchor),
        ])
    }

    private func configureButton(_ button: UIButton, iconName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        button.backgroundColor = Theme.Card.backgroundColor.withAlphaComponent(Theme.Card.backgroundOpacity)
        button.layer.cornerRadius = Theme.Card.cornerRadius
        button.layer.shadowColor = Theme.Shadow.color
        button.layer.shadowOpacity = Theme.Shadow.opacity
        button.layer.shadowOffset = Theme.Shadow.offset
        button.layer.shadowRadius = Theme.Shadow.radius

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Theme.Card.size),
            button.heightAnchor.constraint(equalToConstant: Theme.Card.size),
        ])
    }

    private func setupActions() {
        currentLocationButton.addTarget(self, action: #selector(currentLocationTapped), for: .touchUpInside)
        mapModeButton.addTarget(self, action: #selector(mapModeTapped), for: .touchUpInside)
        bikeLayerButton.addTarget(self, action: #selector(bikeLayerTapped), for: .touchUpInside)
        bikeRefreshButton.addTarget(self, action: #selector(bikeRefreshTapped), for: .touchUpInside)
    }

    private func setupAccessibility() {
        currentLocationButton.accessibilityLabel = "현재 위치"
        currentLocationButton.accessibilityHint = "현재 위치로 이동합니다"

        mapModeButton.accessibilityLabel = "지도 모드"
        mapModeButton.accessibilityHint = "지도 표시 유형을 변경합니다"

        bikeLayerButton.accessibilityLabel = "따릉이 정류소 표시"
        bikeLayerButton.accessibilityHint = "지도에 따릉이 정류소를 표시하거나 숨깁니다"

        bikeRefreshButton.accessibilityLabel = "따릉이 새로고침"
        bikeRefreshButton.accessibilityHint = "따릉이 정류소 정보를 새로고침합니다"
    }

    // MARK: - Actions

    @objc private func currentLocationTapped() {
        onCurrentLocationTapped?()
    }

    @objc private func mapModeTapped() {
        onMapModeTapped?()
    }

    @objc private func bikeLayerTapped() {
        onBikeLayerTapped?()
    }

    @objc private func bikeRefreshTapped() {
        onBikeRefreshTapped?()
    }

    // MARK: - State Updates

    func updateCurrentLocationIcon(for mode: UserLocationPresenter.TrackingMode) {
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
        }

        currentLocationButton.setImage(
            UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium)),
            for: .normal
        )
        currentLocationButton.tintColor = tintColor
    }

    func updateMapModeIcon(isSatellite: Bool) {
        let iconName = isSatellite ? "globe.americas.fill" : "map"

        mapModeButton.setImage(
            UIImage(systemName: iconName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium)),
            for: .normal
        )
    }

    func updateBikeLayerState(isOn: Bool) {
        let tint: UIColor = isOn ? Theme.Colors.primary : Theme.Colors.secondaryLabel
        bikeLayerButton.tintColor = tint
        bikeRefreshButton.isHidden = !isOn
    }

    func setBikeRefreshing(_ refreshing: Bool) {
        bikeRefreshButton.isEnabled = !refreshing
        let alpha: CGFloat = refreshing ? 0.4 : 1
        bikeRefreshButton.alpha = alpha
    }
}
