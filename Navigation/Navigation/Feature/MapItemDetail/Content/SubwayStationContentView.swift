import UIKit

/// 지하철역 실시간 도착 컨텐츠 뷰 — 호선별 섹션, 상/하행 각 2개
final class SubwayStationContentView: UIView {

    // MARK: - Callbacks

    var onLineTapped: ((String) -> Void)?
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
        lbl.text = "실시간 도착 정보가 없습니다"
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
        addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    // MARK: - Public

    func showLoading() {
        loadingLabel.isHidden = false
        emptyLabel.isHidden = true
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    func configure(arrivals: [SubwayArrival], lines: SubwayLines) {
        loadingLabel.isHidden = true
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if arrivals.isEmpty {
            emptyLabel.isHidden = false
            return
        }
        emptyLabel.isHidden = true

        // 호선별 그룹화 (등장 순서 유지)
        var lineOrder: [String] = []
        var grouped: [String: [SubwayArrival]] = [:]
        for arrival in arrivals {
            if grouped[arrival.lineName] == nil {
                lineOrder.append(arrival.lineName)
            }
            grouped[arrival.lineName, default: []].append(arrival)
        }

        for lineName in lineOrder {
            guard let lineArrivals = grouped[lineName] else { continue }
            let color = lines[lineName]?.color ?? "#888888"
            let section = makeLineSection(lineName: lineName, arrivals: lineArrivals, colorHex: color)
            stackView.addArrangedSubview(section)
            stackView.addArrangedSubview(makeSeparator())
        }
    }

    func setRefreshing(_ refreshing: Bool) {
        refreshButton.isEnabled = !refreshing
    }

    // MARK: - Private

    private func makeLineSection(lineName: String, arrivals: [SubwayArrival], colorHex: String) -> UIView {
        // 헤더 (호선명 + 탭)
        let colorBar = UIView()
        colorBar.backgroundColor = UIColor(hex: colorHex) ?? .gray
        colorBar.layer.cornerRadius = 3
        colorBar.widthAnchor.constraint(equalToConstant: 6).isActive = true
        colorBar.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let lineLabel = UILabel()
        lineLabel.text = lineName
        lineLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        lineLabel.textColor = Theme.Colors.label

        let lineStack = UIStackView(arrangedSubviews: [colorBar, lineLabel, UIView()])
        lineStack.axis = .horizontal
        lineStack.spacing = 8
        lineStack.alignment = .center

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        var rows: [UIView] = [lineStack]

        // 방향별로 최대 2개씩 표시
        let directions = Array(Set(arrivals.map(\.direction))).sorted()
        for direction in directions {
            let dirArrivals = arrivals.filter { $0.direction == direction }.prefix(2)
            for arrival in dirArrivals {
                rows.append(makeArrivalRow(arrival))
            }
        }

        let sectionStack = UIStackView(arrangedSubviews: rows)
        sectionStack.axis = .vertical
        sectionStack.spacing = 4
        sectionStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sectionStack)

        NSLayoutConstraint.activate([
            sectionStack.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.md),
            sectionStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.md),
            sectionStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sectionStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // 호선 탭 → 노선 상세
        let tap = UITapGestureRecognizer(target: self, action: #selector(lineTapped(_:)))
        container.addGestureRecognizer(tap)
        container.accessibilityIdentifier = lineName

        return container
    }

    private func makeArrivalRow(_ arrival: SubwayArrival) -> UIView {
        let dirLabel = UILabel()
        dirLabel.text = "  \(arrival.direction)"
        dirLabel.font = Theme.Fonts.caption
        dirLabel.textColor = Theme.Colors.secondaryLabel
        dirLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let destLabel = UILabel()
        destLabel.text = arrival.destination
        destLabel.font = Theme.Fonts.caption
        destLabel.textColor = Theme.Colors.secondaryLabel

        if arrival.isExpress {
            destLabel.text = "⚡ \(arrival.destination)"
        }

        let msgLabel = UILabel()
        msgLabel.text = arrival.arrivalMessage
        msgLabel.font = Theme.Fonts.body
        msgLabel.textColor = Theme.Colors.label
        msgLabel.textAlignment = .right
        msgLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [dirLabel, destLabel, msgLabel])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        return row
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = Theme.Colors.separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    @objc private func lineTapped(_ gesture: UITapGestureRecognizer) {
        guard let lineName = gesture.view?.accessibilityIdentifier else { return }
        onLineTapped?(lineName)
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
