import UIKit
import Combine
import MapKit

final class RoutePreviewDrawerViewController: UIViewController {

    // MARK: - UI Components

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

    private let transportModeSegment: UISegmentedControl = {
        let segment = UISegmentedControl(items: [
            TransportMode.automobile.displayName,
            TransportMode.walking.displayName,
        ])
        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.selectedSegmentIndex = 0
        segment.selectedSegmentTintColor = Theme.Segment.selectedTintColor
        let normalAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: Theme.Segment.normalTextColor]
        let selectedAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: Theme.Segment.selectedTextColor]
        segment.setTitleTextAttributes(normalAttrs, for: .normal)
        segment.setTitleTextAttributes(selectedAttrs, for: .selected)
        return segment
    }()

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.isScrollEnabled = false
        return tableView
    }()

    private let startButton = DrawerActionButton(style: .primary, title: "안내 시작")
    private let virtualDriveButton = DrawerActionButton(style: .secondary, title: "가상 주행")

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Properties

    private let viewModel: RoutePreviewViewModel
    private var cancellables = Set<AnyCancellable>()

    var onStartNavigation: ((Route, TransportMode) -> Void)?
    var onStartVirtualDrive: ((Route, TransportMode) -> Void)?
    var onClose: (() -> Void)?
    var onRoutesChanged: (([Route], Int) -> Void)?

    // MARK: - Init

    init(viewModel: RoutePreviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupActions()
        bindViewModel()

        headerView.setTitle(viewModel.destinationName ?? "목적지")

        Task {
            await viewModel.calculateRoutes()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        // Header: destination name + close
        headerView.addRightAction(closeButton)

        view.addSubview(headerView)
        view.addSubview(transportModeSegment)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)

        let padding = Theme.Drawer.Layout.contentHorizontalPadding

        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Transport mode segment
            transportModeSegment.topAnchor.constraint(
                equalTo: headerView.bottomAnchor,
                constant: Theme.Drawer.Layout.contentTopPadding
            ),
            transportModeSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            transportModeSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            transportModeSegment.heightAnchor.constraint(equalToConstant: Theme.Segment.height),

            // Table view
            tableView.topAnchor.constraint(equalTo: transportModeSegment.bottomAnchor, constant: Theme.Spacing.md),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 180),

            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(RouteOptionCell.self, forCellReuseIdentifier: "RouteOptionCell")
    }

    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        startButton.addTarget(self, action: #selector(startNavigationTapped), for: .touchUpInside)
        virtualDriveButton.addTarget(self, action: #selector(virtualDriveTapped), for: .touchUpInside)
        transportModeSegment.addTarget(self, action: #selector(transportModeChanged), for: .valueChanged)

        transportModeSegment.selectedSegmentIndex = viewModel.transportMode == .automobile ? 0 : 1
        transportModeSegment.accessibilityLabel = "이동수단 선택"
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.routes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] routes in
                guard let self else { return }
                tableView.reloadData()
                if !routes.isEmpty {
                    onRoutesChanged?(routes, viewModel.selectedRouteIndex.value)
                }
            }
            .store(in: &cancellables)

        viewModel.selectedRouteIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self else { return }
                tableView.reloadData()
                let routes = viewModel.routes.value
                if !routes.isEmpty {
                    onRoutesChanged?(routes, index)
                }
            }
            .store(in: &cancellables)

        viewModel.isCalculating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCalc in
                if isCalc {
                    self?.loadingIndicator.startAnimating()
                    self?.startButton.isEnabled = false
                    self?.startButton.alpha = 0.5
                    self?.virtualDriveButton.isEnabled = false
                    self?.virtualDriveButton.alpha = 0.5
                } else {
                    self?.loadingIndicator.stopAnimating()
                    self?.startButton.isEnabled = true
                    self?.startButton.alpha = 1.0
                    self?.virtualDriveButton.isEnabled = true
                    self?.virtualDriveButton.alpha = 1.0
                }
            }
            .store(in: &cancellables)

        viewModel.errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                let alert = UIAlertController(title: "오류", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "확인", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)

    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func startNavigationTapped() {
        guard let selectedRoute = viewModel.getSelectedRoute() else { return }
        onStartNavigation?(selectedRoute, viewModel.transportMode)
    }

    @objc private func virtualDriveTapped() {
        guard let selectedRoute = viewModel.getSelectedRoute() else { return }
        onStartVirtualDrive?(selectedRoute, viewModel.transportMode)
    }

    @objc private func transportModeChanged() {
        let mode: TransportMode = transportModeSegment.selectedSegmentIndex == 0 ? .automobile : .walking
        viewModel.setTransportMode(mode)
        Task { [weak self] in
            await self?.viewModel.calculateRoutes()
        }
    }
}

// MARK: - UITableViewDataSource

extension RoutePreviewDrawerViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.routes.value.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "RouteOptionCell",
            for: indexPath
        ) as? RouteOptionCell else {
            return UITableViewCell()
        }

        let route = viewModel.routes.value[indexPath.row]
        let isSelected = indexPath.row == viewModel.selectedRouteIndex.value
        cell.configure(with: route, isSelected: isSelected)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension RoutePreviewDrawerViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.selectRoute(at: indexPath.row)
    }
}

// MARK: - DrawerFooterProviding

extension RoutePreviewDrawerViewController: DrawerFooterProviding {

    var footerContentView: UIView {
        let container = UIView()
        container.backgroundColor = Theme.Colors.background

        virtualDriveButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(virtualDriveButton)
        container.addSubview(startButton)

        let padding = Theme.Drawer.Layout.contentHorizontalPadding

        NSLayoutConstraint.activate([
            // start 버튼이 container 상하 고정 (더 큰 height 48 기준)
            startButton.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.md),
            startButton.leadingAnchor.constraint(equalTo: virtualDriveButton.trailingAnchor, constant: Theme.Spacing.sm),
            startButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            startButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.md),

            // virtualDrive 는 start 와 centerY 정렬 (자체 height 40 유지)
            virtualDriveButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            virtualDriveButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            virtualDriveButton.widthAnchor.constraint(equalToConstant: 100),
        ])

        return container
    }
}
