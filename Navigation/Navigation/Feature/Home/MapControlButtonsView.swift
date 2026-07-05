import UIKit
import MapKit

final class MapControlButtonsView: UIView {

    // MARK: - Callbacks

    var onCurrentLocationTapped: (() -> Void)?
    var onMapModeTapped: (() -> Void)?
    var onBikeRefreshTapped: (() -> Void)?
    var onPOILayerTapped: (() -> Void)?
    var onLivePulseTapped: (() -> Void)?

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
    private let bikeRefreshButton = UIButton(type: .system)
    private let poiLayerButton = UIButton(type: .system)
    private let livePulseButton = UIButton(type: .system)

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

        // POI 레이어 버튼 — 따릉이/버스 토글 팝업 진입
        configureButton(poiLayerButton, iconName: "square.3.layers.3d")
        stackView.addArrangedSubview(poiLayerButton)

        // 실시간 혼잡(Live Pulse) 진입 버튼
        configureButton(livePulseButton, iconName: "waveform.path.ecg")
        stackView.addArrangedSubview(livePulseButton)

        // 새로고침 버튼 — 따릉이 ON 일 때만 노출. stackView 바깥에서 POI 버튼 좌측에 별도 배치
        configureButton(bikeRefreshButton, iconName: "arrow.clockwise")
        bikeRefreshButton.isHidden = true
        addSubview(bikeRefreshButton)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // refresh 는 POI 레이어 버튼의 좌측에 배치
            bikeRefreshButton.trailingAnchor.constraint(equalTo: poiLayerButton.leadingAnchor, constant: -Theme.Spacing.sm),
            bikeRefreshButton.centerYAnchor.constraint(equalTo: poiLayerButton.centerYAnchor),
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
        bikeRefreshButton.addTarget(self, action: #selector(bikeRefreshTapped), for: .touchUpInside)
        poiLayerButton.addTarget(self, action: #selector(poiLayerTapped), for: .touchUpInside)
        livePulseButton.addTarget(self, action: #selector(livePulseTapped), for: .touchUpInside)
    }

    private func setupAccessibility() {
        currentLocationButton.accessibilityLabel = "현재 위치"
        currentLocationButton.accessibilityHint = "현재 위치로 이동합니다"

        mapModeButton.accessibilityLabel = "지도 모드"
        mapModeButton.accessibilityHint = "지도 표시 유형을 변경합니다"

        bikeRefreshButton.accessibilityLabel = "따릉이 새로고침"
        bikeRefreshButton.accessibilityHint = "따릉이 정류소 정보를 새로고침합니다"

        poiLayerButton.accessibilityLabel = "POI 레이어"
        poiLayerButton.accessibilityHint = "따릉이, 버스 표시를 설정합니다"
    }

    // MARK: - Actions

    @objc private func currentLocationTapped() {
        onCurrentLocationTapped?()
    }

    @objc private func mapModeTapped() {
        onMapModeTapped?()
    }

    @objc private func bikeRefreshTapped() {
        onBikeRefreshTapped?()
    }

    @objc private func poiLayerTapped() {
        onPOILayerTapped?()
    }

    @objc private func livePulseTapped() {
        onLivePulseTapped?()
    }

    /// 실시간 혼잡 모드 ON/OFF 시각 상태
    func updateLivePulseState(isOn: Bool) {
        livePulseButton.tintColor = isOn ? Theme.Colors.primary : Theme.Colors.secondaryLabel
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
        // 따릉이 레이어 ON 일 때만 새로고침 버튼 노출
        bikeRefreshButton.isHidden = !isOn
    }

    func setBikeRefreshing(_ refreshing: Bool) {
        bikeRefreshButton.isEnabled = !refreshing
        let alpha: CGFloat = refreshing ? 0.4 : 1
        bikeRefreshButton.alpha = alpha
    }

    func updatePOILayerState(hasActiveLayer: Bool) {
        poiLayerButton.tintColor = hasActiveLayer ? Theme.Colors.primary : Theme.Colors.secondaryLabel
    }

    // bikeRefreshButton 은 self 의 bounds 좌측 밖에 배치되어 있어 기본 hitTest 로는 탭이 통과됨.
    // 보이는 영역(노출 중 + 활성) 일 때만 hit 으로 확장.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        if !bikeRefreshButton.isHidden, bikeRefreshButton.isEnabled {
            let p = convert(point, to: bikeRefreshButton)
            if bikeRefreshButton.bounds.contains(p) { return true }
        }
        return false
    }
}
