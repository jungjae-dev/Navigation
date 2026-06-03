import UIKit
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "SubwayTimetableDrawer")

/// 지하철 시간표 드로어 — 호선/방향/요일 선택 + 시간 그리드
final class SubwayStationTimetableDrawerViewController: UIViewController {

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - UI

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

    private let lineSegment: UISegmentedControl = {
        let sc = UISegmentedControl()
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private let directionSegment: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["상행/내선", "하행/외선"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let daySegment: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["평일", "토요일", "일요일"])
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
        lbl.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        lbl.textColor = Theme.Colors.label
        lbl.numberOfLines = 0
        return lbl
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let ind = UIActivityIndicatorView(style: .medium)
        ind.translatesAutoresizingMaskIntoConstraints = false
        ind.hidesWhenStopped = true
        return ind
    }()

    // MARK: - State

    private let station: SubwayStation
    private let api: SubwayTimetableAPI
    private var selectedLineIndex: Int = 0
    private var selectedDirection: SubwayTimetableAPI.Direction = .up
    private var selectedDayType: SubwayTimetableAPI.DayType = .weekday

    // MARK: - Init

    init(station: SubwayStation, api: SubwayTimetableAPI = .shared) {
        self.station = station
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
        setupLineSegment()
        Task { await loadTimetable() }
    }

    // MARK: - Setup

    private func setupUI() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addRightAction(closeButton)
        headerView.setTitle("\(station.name) 시간표")

        lineSegment.addTarget(self, action: #selector(lineChanged), for: .valueChanged)
        directionSegment.addTarget(self, action: #selector(directionChanged), for: .valueChanged)
        daySegment.addTarget(self, action: #selector(dayChanged), for: .valueChanged)

        scrollView.addSubview(timesLabel)

        let controls = UIStackView(arrangedSubviews: [lineSegment, directionSegment, daySegment])
        controls.axis = .vertical
        controls.spacing = Theme.Spacing.sm

        let stack = UIStackView(arrangedSubviews: [headerView, controls, scrollView])
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

    private func setupLineSegment() {
        for (i, line) in station.lines.enumerated() {
            lineSegment.insertSegment(withTitle: line, at: i, animated: false)
        }
        if !station.lines.isEmpty { lineSegment.selectedSegmentIndex = 0 }

        // 2호선이면 방향 레이블 변경
        updateDirectionLabels()
    }

    private func updateDirectionLabels() {
        let currentLine = station.lines[safe: selectedLineIndex] ?? ""
        if currentLine == "2호선" {
            directionSegment.setTitle("내선", forSegmentAt: 0)
            directionSegment.setTitle("외선", forSegmentAt: 1)
        } else {
            directionSegment.setTitle("상행", forSegmentAt: 0)
            directionSegment.setTitle("하행", forSegmentAt: 1)
        }
    }

    // MARK: - Load

    private func loadTimetable() async {
        loadingIndicator.startAnimating()
        timesLabel.text = nil

        // 역 코드는 station.stationCode 사용 (OA-101은 4자리 코드)
        do {
            let entries = try await api.fetchTimetable(
                stationCode: station.stationCode,
                direction: selectedDirection,
                dayType: selectedDayType
            )
            await MainActor.run { renderEntries(entries) }
        } catch {
            logger.error("Subway timetable error: \(error.localizedDescription)")
            await MainActor.run { timesLabel.text = "시간표를 불러올 수 없습니다" }
        }
        loadingIndicator.stopAnimating()
    }

    private func renderEntries(_ entries: [SubwayTimetableAPI.TimetableEntry]) {
        if entries.isEmpty {
            timesLabel.text = "운행 정보 없음"
            return
        }
        // 시간대별 그룹
        var grouped: [String: [(String, String)]] = [:]
        for entry in entries {
            let parts = entry.departureTime.split(separator: ":").map(String.init)
            guard parts.count >= 2 else { continue }
            let hour = parts[0]
            let minute = parts[1]
            grouped[hour, default: []].append((minute, entry.destination))
        }
        let sortedHours = grouped.keys.sorted()
        let lines = sortedHours.map { hour -> String in
            let mins = (grouped[hour] ?? []).sorted { $0.0 < $1.0 }.map { $0.0 }.joined(separator: " ")
            return "\(hour)시  \(mins)"
        }
        timesLabel.text = lines.joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func closeTapped() { onClose?() }

    @objc private func lineChanged() {
        selectedLineIndex = lineSegment.selectedSegmentIndex
        updateDirectionLabels()
        Task { await loadTimetable() }
    }

    @objc private func directionChanged() {
        selectedDirection = directionSegment.selectedSegmentIndex == 0 ? .up : .down
        Task { await loadTimetable() }
    }

    @objc private func dayChanged() {
        switch daySegment.selectedSegmentIndex {
        case 0: selectedDayType = .weekday
        case 1: selectedDayType = .saturday
        default: selectedDayType = .sunday
        }
        Task { await loadTimetable() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
