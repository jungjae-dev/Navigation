import UIKit

/// 버스 정류소 도착 정보 컨텐츠 뷰 — 노선별 도착 정보 목록
final class BusStopContentView: UIView {

    // MARK: - Callbacks

    var onRouteTapped: ((BusArrival) -> Void)?
    var onRefreshTapped: (() -> Void)?

    // MARK: - UI

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let loadingLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "도착 정보를 불러오는 중..."
        lbl.font = Theme.Fonts.body
        lbl.textColor = Theme.Colors.secondaryLabel
        lbl.textAlignment = .center
        return lbl
    }()

    private let emptyLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "경유 노선 정보가 없습니다"
        lbl.font = Theme.Fonts.body
        lbl.textColor = Theme.Colors.secondaryLabel
        lbl.textAlignment = .center
        lbl.isHidden = true
        return lbl
    }()

    private let refreshButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        btn.setTitle(" 새로고침", for: .normal)
        btn.tintColor = Theme.Colors.primary
        btn.titleLabel?.font = Theme.Fonts.caption
        return btn
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

        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [UIView(), refreshButton])
        headerRow.axis = .horizontal

        let outer = UIStackView(arrangedSubviews: [headerRow, loadingLabel, emptyLabel, stackView])
        outer.axis = .vertical
        outer.spacing = Theme.Spacing.sm
        outer.translatesAutoresizingMaskIntoConstraints = false

        // 도착 노선이 많아 고정 높이(드로어 detent)를 초과할 수 있으므로 스크롤 가능하게 구성
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        scrollView.addSubview(outer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            outer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            outer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            outer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    // MARK: - Public

    func showLoading() {
        loadingLabel.isHidden = false
        emptyLabel.isHidden = true
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    func configure(arrivals: [BusArrival]) {
        loadingLabel.isHidden = true
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if arrivals.isEmpty {
            emptyLabel.isHidden = false
            return
        }
        emptyLabel.isHidden = true

        for arrival in arrivals {
            let row = makeArrivalRow(arrival)
            stackView.addArrangedSubview(row)
            let sep = makeSeparator()
            stackView.addArrangedSubview(sep)
        }
    }

    func setRefreshing(_ refreshing: Bool) {
        refreshButton.isEnabled = !refreshing
    }

    // MARK: - Private

    private func makeArrivalRow(_ arrival: BusArrival) -> UIView {
        let routeColorHex = arrival.routeType.color
        let colorDot = UIView()
        // 노선 색은 도메인 의미색. 미지정 시 중립색(accent 절제).
        colorDot.backgroundColor = UIColor(hex: routeColorHex) ?? Theme.Colors.secondaryLabel
        colorDot.layer.cornerRadius = 4
        colorDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        colorDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let routeLabel = UILabel()
        routeLabel.text = arrival.routeName
        routeLabel.font = Theme.Fonts.headline
        routeLabel.adjustsFontForContentSizeCategory = true
        routeLabel.textColor = Theme.Colors.label

        let directionLabel = UILabel()
        directionLabel.text = arrival.direction
        directionLabel.font = Theme.Fonts.caption
        directionLabel.textColor = Theme.Colors.secondaryLabel

        let routeStack = UIStackView(arrangedSubviews: [colorDot, routeLabel, directionLabel])
        routeStack.axis = .horizontal
        routeStack.spacing = 6
        routeStack.alignment = .center

        let firstLabel = UILabel()
        firstLabel.text = arrival.firstArrivalMessage
        firstLabel.font = Theme.Fonts.body
        firstLabel.textColor = arrival.firstArrivalMessage.contains("운행 종료") ? Theme.Colors.secondaryLabel : Theme.Colors.label
        firstLabel.textAlignment = .right

        let secondLabel = UILabel()
        secondLabel.text = arrival.secondArrivalMessage
        secondLabel.font = Theme.Fonts.caption
        secondLabel.textColor = Theme.Colors.secondaryLabel
        secondLabel.textAlignment = .right

        let arrivalStack = UIStackView(arrangedSubviews: [firstLabel, secondLabel])
        arrivalStack.axis = .vertical
        arrivalStack.alignment = .trailing
        arrivalStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [routeStack, arrivalStack])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.md),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.md),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // 탭 제스처
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        container.addGestureRecognizer(tap)
        container.tag = stackView.arrangedSubviews.count
        container.accessibilityIdentifier = arrival.routeId
        // arrival 저장용 — tag 대신 accessibilityIdentifier 로 routeId 저장
        arrivalRows[arrival.routeId] = arrival

        return container
    }

    private var arrivalRows: [String: BusArrival] = [:]

    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = Theme.Colors.separator
        view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return view
    }

    @objc private func rowTapped(_ gesture: UITapGestureRecognizer) {
        guard let container = gesture.view,
              let routeId = container.accessibilityIdentifier,
              let arrival = arrivalRows[routeId] else { return }
        onRouteTapped?(arrival)
    }

    @objc private func refreshTapped() {
        onRefreshTapped?()
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else { return nil }
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}
