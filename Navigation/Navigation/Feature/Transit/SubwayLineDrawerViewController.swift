import UIKit
import MapKit
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "SubwayLineDrawer")

/// 지하철 노선 상세 드로어 — 호선명 헤더 + 역 목록
final class SubwayLineDrawerViewController: UIViewController {

    // MARK: - Callbacks

    var onClose: (() -> Void)?
    var onStationTapped: ((SubwayStation) -> Void)?

    // MARK: - UI

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

    private let tableView: UITableView = {
        let tv = UITableView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "StationCell")
        return tv
    }()

    // MARK: - State

    private let lineName: String
    private let lineInfo: SubwayLineInfo
    private let allStations: [SubwayStation]
    private var lineStations: [SubwayStation] = []
    private var currentStationCode: String?

    // MARK: - Init

    init(lineName: String, lineInfo: SubwayLineInfo, allStations: [SubwayStation], currentStationCode: String? = nil) {
        self.lineName = lineName
        self.lineInfo = lineInfo
        self.allStations = allStations
        self.currentStationCode = currentStationCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Card.backgroundColor
        buildStationList()
        setupUI()
        scrollToCurrentStation()
    }

    // MARK: - Setup

    private func buildStationList() {
        let stationMap = Dictionary(uniqueKeysWithValues: allStations.map { ($0.stationCode, $0) })
        lineStations = lineInfo.stationCodes.compactMap { stationMap[$0] }
        logger.info("SubwayLine \(self.lineName): \(self.lineStations.count) stations loaded")
    }

    private func setupUI() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addRightAction(closeButton)

        // 호선 색상을 아이콘으로 표시
        let colorHex = lineInfo.color
        let lineColor = UIColor(hex: colorHex) ?? .gray
        let dotImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { ctx in
            lineColor.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        headerView.setLeftIcon(dotImage, size: 12)
        headerView.setTitle(lineName)

        [headerView, tableView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        tableView.delegate = self
        tableView.dataSource = self

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.md),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: Theme.Spacing.sm),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func scrollToCurrentStation() {
        guard let code = currentStationCode,
              let idx = lineStations.firstIndex(where: { $0.stationCode == code }) else { return }
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: IndexPath(row: idx, section: 0), at: .middle, animated: false)
        }
    }

    @objc private func closeTapped() { onClose?() }
}

// MARK: - UITableViewDataSource / Delegate

extension SubwayLineDrawerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lineStations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StationCell", for: indexPath)
        let station = lineStations[indexPath.row]
        let isCurrent = station.stationCode == currentStationCode

        var config = cell.defaultContentConfiguration()
        config.text = station.name
        config.textProperties.font = isCurrent
            ? UIFont.systemFont(ofSize: 16, weight: .semibold)
            : Theme.Fonts.body
        config.textProperties.color = isCurrent ? Theme.Colors.primary : Theme.Colors.label

        // 환승역 표시
        if station.lines.count > 1 {
            let other = station.lines.filter { $0 != lineName }.joined(separator: ", ")
            config.secondaryText = "환승: \(other)"
            config.secondaryTextProperties.font = Theme.Fonts.caption
            config.secondaryTextProperties.color = Theme.Colors.secondaryLabel
        }

        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        cell.accessoryType = isCurrent ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onStationTapped?(lineStations[indexPath.row])
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
