import UIKit
import MapKit
import OSLog

private let logger = Logger(subsystem: "nav.transit", category: "BusRouteDrawer")

/// 버스 노선 상세 드로어 — 노선명/기종점 헤더 + 경유 정류소 목록
final class BusRouteDrawerViewController: UIViewController {

    // MARK: - Callbacks

    var onClose: (() -> Void)?
    var onStopTapped: ((BusRouteStop) -> Void)?

    // MARK: - UI

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .back)

    private let tableView: UITableView = {
        let tv = UITableView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "StopCell")
        return tv
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - State

    private let arrival: BusArrival
    private let api: BusAPIClient
    private var stops: [BusRouteStop] = []
    private var currentStopArsId: String?

    // MARK: - Init

    init(arrival: BusArrival, currentStopArsId: String? = nil, api: BusAPIClient = .shared) {
        self.arrival = arrival
        self.currentStopArsId = currentStopArsId
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
        headerView.setTitle("\(arrival.routeName)번 → \(arrival.direction)")
        Task { await loadStops() }
    }

    // MARK: - Setup

    private func setupUI() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addLeftAction(closeButton)

        [headerView, tableView, loadingIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        tableView.delegate = self
        tableView.dataSource = self

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.md),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: Theme.Spacing.md),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Load

    private func loadStops() async {
        loadingIndicator.startAnimating()
        tableView.isHidden = true

        do {
            stops = try await api.fetchRouteStops(routeId: arrival.routeId)
            tableView.reloadData()
            tableView.isHidden = false

            // 현재 정류소 강조
            if let arsId = currentStopArsId,
               let idx = stops.firstIndex(where: { $0.arsId == arsId }) {
                tableView.scrollToRow(at: IndexPath(row: idx, section: 0), at: .middle, animated: false)
            }
        } catch {
            logger.error("Route stops load failed: \(error.localizedDescription)")
        }
        loadingIndicator.stopAnimating()
    }

    // MARK: - Actions

    @objc private func closeTapped() { onClose?() }
}

// MARK: - UITableViewDataSource / Delegate

extension BusRouteDrawerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        stops.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StopCell", for: indexPath)
        let stop = stops[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = stop.name
        config.textProperties.font = Theme.Fonts.body

        let isCurrent = stop.arsId == currentStopArsId
        config.textProperties.color = isCurrent ? Theme.Colors.primary : Theme.Colors.label
        if isCurrent {
            config.textProperties.font = Theme.Fonts.headline
        }

        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // 탭 시 지도 카메라 이동 (드로어 유지)
        onStopTapped?(stops[indexPath.row])
    }
}
