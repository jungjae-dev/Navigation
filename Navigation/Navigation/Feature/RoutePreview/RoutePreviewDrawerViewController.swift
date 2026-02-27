import UIKit
import Combine
import MapKit

final class RoutePreviewDrawerViewController: UIViewController {

    // MARK: - Constants

    static let titleBarHeight: CGFloat = 44

    // MARK: - UI Components

    private let destinationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.label
        return label
    }()

    private let favoriteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "star")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.primary
        return button
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "xmark.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        return button
    }()

    private let titleSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.separator
        return view
    }()

    private let transportModeSegment: UISegmentedControl = {
        let segment = UISegmentedControl(items: [
            TransportMode.automobile.displayName,
            TransportMode.walking.displayName,
        ])
        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.selectedSegmentIndex = 0
        segment.selectedSegmentTintColor = Theme.Colors.primary
        let normalAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: Theme.Colors.label]
        let selectedAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
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

    private let startButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("안내 시작", for: .normal)
        button.titleLabel?.font = Theme.Fonts.headline
        button.backgroundColor = Theme.Colors.primary
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = Theme.CornerRadius.medium
        return button
    }()

    private let virtualDriveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("가상 주행", for: .normal)
        button.titleLabel?.font = Theme.Fonts.subheadline
        button.backgroundColor = Theme.Colors.secondaryBackground
        button.setTitleColor(Theme.Colors.primary, for: .normal)
        button.layer.cornerRadius = Theme.CornerRadius.medium
        button.layer.borderColor = Theme.Colors.primary.cgColor
        button.layer.borderWidth = 1
        return button
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Properties

    private let viewModel: RoutePreviewViewModel
    private var cancellables = Set<AnyCancellable>()

    var onStartNavigation: ((MKRoute, TransportMode) -> Void)?
    var onStartVirtualDrive: ((MKRoute, TransportMode) -> Void)?
    var onClose: (() -> Void)?
    var onRoutesChanged: (([MKRoute], Int) -> Void)?

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

        destinationLabel.text = viewModel.destinationName ?? "목적지"

        Task {
            await viewModel.calculateRoutes()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        view.addSubview(destinationLabel)
        view.addSubview(favoriteButton)
        view.addSubview(closeButton)
        view.addSubview(titleSeparator)
        view.addSubview(transportModeSegment)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(virtualDriveButton)
        view.addSubview(startButton)

        NSLayoutConstraint.activate([
            // Title bar
            destinationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            destinationLabel.centerYAnchor.constraint(equalTo: view.topAnchor, constant: Self.titleBarHeight / 2),
            destinationLabel.trailingAnchor.constraint(lessThanOrEqualTo: favoriteButton.leadingAnchor, constant: -Theme.Spacing.sm),

            favoriteButton.centerYAnchor.constraint(equalTo: destinationLabel.centerYAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -Theme.Spacing.xs),
            favoriteButton.widthAnchor.constraint(equalToConstant: 40),
            favoriteButton.heightAnchor.constraint(equalToConstant: 40),

            closeButton.centerYAnchor.constraint(equalTo: destinationLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            // Separator
            titleSeparator.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.titleBarHeight),
            titleSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            // Transport mode segment
            transportModeSegment.topAnchor.constraint(equalTo: titleSeparator.bottomAnchor, constant: Theme.Spacing.md),
            transportModeSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            transportModeSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            transportModeSegment.heightAnchor.constraint(equalToConstant: 32),

            // Table view
            tableView.topAnchor.constraint(equalTo: transportModeSegment.bottomAnchor, constant: Theme.Spacing.md),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 180),

            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            // Buttons
            virtualDriveButton.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: Theme.Spacing.md),
            virtualDriveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            virtualDriveButton.widthAnchor.constraint(equalToConstant: 100),
            virtualDriveButton.heightAnchor.constraint(equalToConstant: 48),

            startButton.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: Theme.Spacing.md),
            startButton.leadingAnchor.constraint(equalTo: virtualDriveButton.trailingAnchor, constant: Theme.Spacing.sm),
            startButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            startButton.heightAnchor.constraint(equalToConstant: 48),
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
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
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

        viewModel.isFavorite
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFav in
                let imageName = isFav ? "star.fill" : "star"
                let image = UIImage(systemName: imageName)?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
                self?.favoriteButton.setImage(image, for: .normal)
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

    @objc private func favoriteTapped() {
        viewModel.toggleFavorite()
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
