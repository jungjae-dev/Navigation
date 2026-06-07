import UIKit
import MapKit

final class MapControlButtonsView: UIView {

    // MARK: - Callbacks

    var onCurrentLocationTapped: (() -> Void)?
    var onMapModeTapped: (() -> Void)?
    var onBikeRefreshTapped: (() -> Void)?
    var onPOILayerTapped: (() -> Void)?

    // MARK: - UI

    /// 애플 지도풍 단일 그룹 컨테이너 — 상시 버튼을 하버라인 구분선으로 묶고 그림자 1개.
    private let groupContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Card.backgroundColor
        view.layer.cornerRadius = Theme.CornerRadius.large
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = Theme.Shadow.offset
        view.layer.shadowRadius = Theme.Shadow.radius
        return view
    }()

    private let groupStack: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.spacing = 0
        return sv
    }()

    private let currentLocationButton = UIButton(type: .system)
    private let mapModeButton = UIButton(type: .system)
    private let poiLayerButton = UIButton(type: .system)
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
        addSubview(groupContainer)
        groupContainer.addSubview(groupStack)

        // 상시 노출 컨트롤: 현재 위치 / 지도 모드 / POI 레이어 — 하나의 그룹으로 묶음
        configureGroupedButton(currentLocationButton, iconName: "location")
        groupStack.addArrangedSubview(currentLocationButton)
        groupStack.addArrangedSubview(makeDivider())

        configureGroupedButton(mapModeButton, iconName: "map")
        groupStack.addArrangedSubview(mapModeButton)
        groupStack.addArrangedSubview(makeDivider())

        // POI 레이어 — 따릉이/버스 토글 팝업 진입
        configureGroupedButton(poiLayerButton, iconName: "square.3.layers.3d")
        groupStack.addArrangedSubview(poiLayerButton)

        // 새로고침 — 따릉이 ON 일 때만 노출. 맥락 버튼이라 그룹 좌측에 별도 플로팅 카드로 배치
        configureFloatingButton(bikeRefreshButton, iconName: "arrow.clockwise")
        bikeRefreshButton.isHidden = true
        addSubview(bikeRefreshButton)

        NSLayoutConstraint.activate([
            // self 의 bounds == 그룹 컨테이너 (POI 팝업 sourceView 앵커가 그룹을 가리키도록)
            groupContainer.topAnchor.constraint(equalTo: topAnchor),
            groupContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            groupContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            groupContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            groupContainer.widthAnchor.constraint(equalToConstant: Theme.Card.size),

            groupStack.topAnchor.constraint(equalTo: groupContainer.topAnchor),
            groupStack.leadingAnchor.constraint(equalTo: groupContainer.leadingAnchor),
            groupStack.trailingAnchor.constraint(equalTo: groupContainer.trailingAnchor),
            groupStack.bottomAnchor.constraint(equalTo: groupContainer.bottomAnchor),

            // refresh 는 그룹의 좌측에 배치
            bikeRefreshButton.trailingAnchor.constraint(equalTo: groupContainer.leadingAnchor, constant: -Theme.Spacing.sm),
            bikeRefreshButton.centerYAnchor.constraint(equalTo: currentLocationButton.centerYAnchor),
        ])
    }

    /// 그룹 내부 버튼 — 개별 배경/그림자/곡률 없음(컨테이너가 제공). 정사각 탭 영역만.
    private func configureGroupedButton(_ button: UIButton, iconName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(symbolImage(iconName), for: .normal)
        button.tintColor = Theme.Colors.secondaryLabel
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Theme.Card.size),
            button.heightAnchor.constraint(equalToConstant: Theme.Card.size),
        ])
    }

    /// 별도 플로팅 카드 버튼(맥락 버튼용) — 자체 배경/그림자/곡률.
    private func configureFloatingButton(_ button: UIButton, iconName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(symbolImage(iconName), for: .normal)
        button.tintColor = Theme.Colors.secondaryLabel
        button.backgroundColor = Theme.Card.backgroundColor
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

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = Theme.Colors.separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1 / UITraitCollection.current.displayScale).isActive = true
        return divider
    }

    private func symbolImage(_ iconName: String) -> UIImage? {
        UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium))
    }

    private func setupActions() {
        currentLocationButton.addTarget(self, action: #selector(currentLocationTapped), for: .touchUpInside)
        mapModeButton.addTarget(self, action: #selector(mapModeTapped), for: .touchUpInside)
        bikeRefreshButton.addTarget(self, action: #selector(bikeRefreshTapped), for: .touchUpInside)
        poiLayerButton.addTarget(self, action: #selector(poiLayerTapped), for: .touchUpInside)
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
            tintColor = Theme.Colors.accent
        case .followWithHeading:
            iconName = "location.north.line.fill"
            tintColor = Theme.Colors.accent
        }

        currentLocationButton.setImage(symbolImage(iconName), for: .normal)
        currentLocationButton.tintColor = tintColor
    }

    func updateMapModeIcon(isSatellite: Bool) {
        let iconName = isSatellite ? "globe.americas.fill" : "map"
        mapModeButton.setImage(symbolImage(iconName), for: .normal)
    }

    func updateBikeLayerState(isOn: Bool) {
        // 따릉이 레이어 ON 일 때만 새로고침 버튼 노출
        bikeRefreshButton.isHidden = !isOn
    }

    func setBikeRefreshing(_ refreshing: Bool) {
        bikeRefreshButton.isEnabled = !refreshing
        bikeRefreshButton.alpha = refreshing ? 0.4 : 1
    }

    func updatePOILayerState(hasActiveLayer: Bool) {
        // 활성 상태에만 accent (절제)
        poiLayerButton.tintColor = hasActiveLayer ? Theme.Colors.accent : Theme.Colors.secondaryLabel
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
