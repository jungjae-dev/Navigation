import UIKit
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusTimetableDrawer")

/// 버스 정류소 운행정보 드로어 — 노선별 첫차/막차/배차간격
/// (서울 버스 API에는 분단위 시간표가 없어 첫차/막차/배차간격으로 표시)
final class BusStopTimetableDrawerViewController: UIViewController {

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - UI

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .back)

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let rowsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let emptyLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = Theme.Fonts.body
        lbl.textColor = Theme.Colors.secondaryLabel
        lbl.textAlignment = .center
        lbl.numberOfLines = 0
        lbl.isHidden = true
        return lbl
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - State

    private let busStop: BusStop
    private let initialArrivals: [BusArrival]
    private let api: BusAPIClient
    private var loadedArrivals: [BusArrival] = []

    // MARK: - Init

    init(busStop: BusStop, arrivals: [BusArrival], api: BusAPIClient = .shared) {
        self.busStop = busStop
        self.initialArrivals = arrivals
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Card.backgroundColor
        setupUI()
        if initialArrivals.isEmpty {
            Task { await fetchArrivalsAndRender() }
        } else {
            loadedArrivals = initialArrivals
            renderRows()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addLeftAction(closeButton)
        headerView.setTitle("\(busStop.name) 운행정보")

        scrollView.addSubview(rowsStack)

        let stack = UIStackView(arrangedSubviews: [headerView, scrollView])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.md
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(emptyLabel)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.md),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Theme.Spacing.xl),

            rowsStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Load

    private func fetchArrivalsAndRender() async {
        loadingIndicator.startAnimating()
        logger.info("[BusTimetable] fetch arrivals for arsId=\(self.busStop.arsId)")
        do {
            loadedArrivals = try await api.fetchArrivals(arsId: busStop.arsId)
            logger.info("[BusTimetable] arrivals=\(self.loadedArrivals.count) for arsId=\(self.busStop.arsId)")
        } catch {
            logger.error("[BusTimetable] fetch failed: \(error.localizedDescription)")
        }
        loadingIndicator.stopAnimating()
        renderRows()
    }

    private func renderRows() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !loadedArrivals.isEmpty else {
            emptyLabel.text = "경유 노선 운행정보가 없습니다"
            emptyLabel.isHidden = false
            return
        }
        emptyLabel.isHidden = true

        for arrival in loadedArrivals {
            rowsStack.addArrangedSubview(makeRow(arrival))
            rowsStack.addArrangedSubview(makeSeparator())
        }
    }

    private func makeRow(_ arrival: BusArrival) -> UIView {
        let colorDot = UIView()
        colorDot.backgroundColor = UIColor(hex: arrival.routeType.color) ?? Theme.Colors.primary
        colorDot.layer.cornerRadius = 4
        colorDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        colorDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let routeLabel = UILabel()
        routeLabel.text = arrival.routeName
        routeLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        routeLabel.textColor = Theme.Colors.label

        let directionLabel = UILabel()
        directionLabel.text = arrival.direction.isEmpty ? nil : "\(arrival.direction) 방면"
        directionLabel.font = Theme.Fonts.caption
        directionLabel.textColor = Theme.Colors.secondaryLabel

        let titleStack = UIStackView(arrangedSubviews: [colorDot, routeLabel, directionLabel])
        titleStack.axis = .horizontal
        titleStack.spacing = 6
        titleStack.alignment = .center

        let infoLabel = UILabel()
        infoLabel.font = Theme.Fonts.body
        infoLabel.textColor = Theme.Colors.secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.text = scheduleText(arrival)

        let row = UIStackView(arrangedSubviews: [titleStack, infoLabel])
        row.axis = .vertical
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.md),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.md),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func scheduleText(_ arrival: BusArrival) -> String {
        var parts: [String] = []
        if !arrival.firstTime.isEmpty || !arrival.lastTime.isEmpty {
            parts.append("첫차 \(formatTime(arrival.firstTime)) · 막차 \(formatTime(arrival.lastTime))")
        }
        if !arrival.term.isEmpty, arrival.term != "0" {
            parts.append("배차간격 약 \(arrival.term)분")
        }
        return parts.isEmpty ? "운행정보 없음" : parts.joined(separator: "\n")
    }

    /// "0400" → "04:00"
    private func formatTime(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard digits.count == 4 else { return raw.isEmpty ? "-" : raw }
        let h = digits.prefix(2)
        let m = digits.suffix(2)
        return "\(h):\(m)"
    }

    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = Theme.Colors.separator
        view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return view
    }

    // MARK: - Actions

    @objc private func closeTapped() { onClose?() }
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
