import UIKit
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusTimetableDrawer")

/// 버스 정류소 시간표 드로어 — 노선 선택 + 평일/토/일 탭 + 시간 그리드
final class BusStopTimetableDrawerViewController: UIViewController {

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - UI

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

    private let routePicker: UISegmentedControl = {
        let sc = UISegmentedControl()
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private let daySegment: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["평일", "토요일", "일요일/공휴일"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let timesLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        lbl.textColor = Theme.Colors.label
        lbl.numberOfLines = 0
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
    private let arrivals: [BusArrival]
    private let api: BusAPIClient
    private var selectedRouteIndex: Int = 0
    private var selectedDayType: BusAPIClient.DayType = .weekday

    // MARK: - Init

    init(busStop: BusStop, arrivals: [BusArrival], api: BusAPIClient = .shared) {
        self.busStop = busStop
        self.arrivals = arrivals
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
        setupRouteSegment()
        Task { await loadTimetable() }
    }

    // MARK: - Setup

    private func setupUI() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addRightAction(closeButton)
        headerView.setTitle("\(busStop.name) 시간표")

        daySegment.addTarget(self, action: #selector(dayChanged), for: .valueChanged)
        routePicker.addTarget(self, action: #selector(routeChanged), for: .valueChanged)

        scrollView.addSubview(timesLabel)

        let stack = UIStackView(arrangedSubviews: [headerView, routePicker, daySegment, scrollView])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.md
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.md),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Theme.Spacing.xl),

            timesLabel.topAnchor.constraint(equalTo: scrollView.topAnchor),
            timesLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            timesLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            timesLabel.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            timesLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupRouteSegment() {
        for (i, arrival) in arrivals.enumerated() {
            routePicker.insertSegment(withTitle: arrival.routeName, at: i, animated: false)
        }
        if !arrivals.isEmpty { routePicker.selectedSegmentIndex = 0 }
    }

    // MARK: - Load

    private func loadTimetable() async {
        guard !arrivals.isEmpty else { return }
        loadingIndicator.startAnimating()
        timesLabel.text = nil

        let arrival = arrivals[selectedRouteIndex]
        do {
            let times = try await api.fetchTimetable(
                arsId: busStop.arsId,
                routeId: arrival.routeId,
                dayType: selectedDayType
            )
            await MainActor.run { renderTimes(times) }
        } catch {
            logger.error("Timetable fetch error: \(error.localizedDescription)")
            await MainActor.run { timesLabel.text = "시간표를 불러올 수 없습니다" }
        }
        loadingIndicator.stopAnimating()
    }

    private func renderTimes(_ times: [String]) {
        if times.isEmpty {
            timesLabel.text = "운행 정보 없음"
            return
        }
        // 시간대별 그룹 (HH: MM MM MM ...)
        var grouped: [String: [String]] = [:]
        for time in times {
            let parts = time.split(separator: ":").map(String.init)
            guard parts.count >= 2 else { continue }
            let hour = parts[0]
            let minute = parts[1]
            grouped[hour, default: []].append(minute)
        }
        let sortedHours = grouped.keys.sorted()
        let lines = sortedHours.map { hour -> String in
            let mins = (grouped[hour] ?? []).sorted().joined(separator: " ")
            return "\(hour)시  \(mins)"
        }
        timesLabel.text = lines.joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func closeTapped() { onClose?() }

    @objc private func dayChanged() {
        switch daySegment.selectedSegmentIndex {
        case 0: selectedDayType = .weekday
        case 1: selectedDayType = .saturday
        default: selectedDayType = .sunday
        }
        Task { await loadTimetable() }
    }

    @objc private func routeChanged() {
        selectedRouteIndex = routePicker.selectedSegmentIndex
        Task { await loadTimetable() }
    }
}
