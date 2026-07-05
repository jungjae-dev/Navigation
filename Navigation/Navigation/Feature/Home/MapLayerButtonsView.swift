import UIKit

/// 좌측 데이터 레이어 버튼 (아이콘 전용 — 우측 지도조작 버튼과 동일 디자인).
/// 따릉이·버스 = 오버레이 토글 / 실시간 혼잡 = 모드. 혼잡 ON 시 오버레이는 disable.
/// 따릉이 새로고침은 따릉이 버튼에 종속 배치(따릉이 ON일 때 우측에 등장).
final class MapLayerButtonsView: UIView {

    // MARK: - Callbacks
    var onBike: (() -> Void)?
    var onBus: (() -> Void)?
    var onCongestion: (() -> Void)?
    var onBikeRefresh: (() -> Void)?

    // MARK: - Buttons
    private let bikeButton = UIButton(type: .system)
    private let busButton = UIButton(type: .system)
    private let congestionButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)

    private var bikeOn = false
    private var congestionOn = false

    private let stack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.alignment = .leading
        s.spacing = Theme.Spacing.sm
        return s
    }()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        configureButton(bikeButton, icon: "bicycle")
        configureButton(busButton, icon: "bus")
        configureButton(congestionButton, icon: "chart.bar.xaxis")
        configureButton(refreshButton, icon: "arrow.clockwise")
        refreshButton.isHidden = true

        // 따릉이 행: [따릉이] [새로고침] — 새로고침은 따릉이에 종속
        let bikeRow = UIStackView(arrangedSubviews: [bikeButton, refreshButton])
        bikeRow.axis = .horizontal
        bikeRow.spacing = Theme.Spacing.sm

        // 순서: 혼잡 ↑ / 버스 / 따릉이(+새로고침) ↓ — 새로고침이 붙는 따릉이를 맨 아래로
        stack.addArrangedSubview(congestionButton)
        stack.addArrangedSubview(busButton)
        stack.addArrangedSubview(bikeRow)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        bikeButton.addTarget(self, action: #selector(bikeTapped), for: .touchUpInside)
        busButton.addTarget(self, action: #selector(busTapped), for: .touchUpInside)
        congestionButton.addTarget(self, action: #selector(congestionTapped), for: .touchUpInside)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)

        setActive(bikeButton, on: false)
        setActive(busButton, on: false)
        setActive(congestionButton, on: false)

        bikeButton.accessibilityLabel = "따릉이 표시"
        busButton.accessibilityLabel = "버스 정류소 표시"
        congestionButton.accessibilityLabel = "실시간 혼잡"
        refreshButton.accessibilityLabel = "따릉이 새로고침"
    }

    // MARK: - Actions
    @objc private func bikeTapped() { onBike?() }
    @objc private func busTapped() { onBus?() }
    @objc private func congestionTapped() { onCongestion?() }
    @objc private func refreshTapped() { onBikeRefresh?() }

    // MARK: - State
    func setBike(on: Bool) {
        bikeOn = on
        setActive(bikeButton, on: on)
        refreshButton.isHidden = !(on && !congestionOn)
    }
    func setBus(on: Bool) { setActive(busButton, on: on) }

    /// 혼잡 ON → 오버레이(따릉이·버스·새로고침) 숨김, OFF → 복원. 애니메이션.
    func setCongestion(on: Bool) {
        congestionOn = on
        setActive(congestionButton, on: on)
        UIView.animate(withDuration: 0.25) {
            self.bikeButton.isHidden = on
            self.busButton.isHidden = on
            self.refreshButton.isHidden = on || !self.bikeOn
            self.bikeButton.alpha = on ? 0 : 1
            self.busButton.alpha = on ? 0 : 1
            self.refreshButton.alpha = on ? 0 : 1
            self.superview?.layoutIfNeeded()
        }
    }
    func setBikeRefreshing(_ refreshing: Bool) {
        refreshButton.isEnabled = !refreshing
        refreshButton.alpha = refreshing ? 0.4 : 1
    }

    // MARK: - 스타일 (우측 MapControlButtonsView와 동일)
    private func configureButton(_ button: UIButton, icon: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: icon)?
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

    private func setActive(_ button: UIButton, on: Bool) {
        button.tintColor = on ? Theme.Colors.primary : Theme.Colors.secondaryLabel
    }
}
