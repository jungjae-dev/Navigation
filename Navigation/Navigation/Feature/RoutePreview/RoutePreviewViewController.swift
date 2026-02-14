import UIKit
import Combine
import MapKit

final class RoutePreviewViewController: UIViewController {

    // MARK: - UI Components

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = Theme.Colors.label
        button.backgroundColor = Theme.Colors.secondaryBackground
        button.layer.cornerRadius = 20
        button.layer.shadowColor = Theme.Shadow.color
        button.layer.shadowOpacity = Theme.Shadow.opacity
        button.layer.shadowOffset = Theme.Shadow.offset
        button.layer.shadowRadius = Theme.Shadow.radius
        return button
    }()

    private let bottomContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.background
        view.layer.cornerRadius = Theme.CornerRadius.large
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = Theme.Shadow.radius
        return view
    }()

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

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Properties

    private let viewModel: RoutePreviewViewModel
    private let mapViewController: MapViewController
    private var cancellables = Set<AnyCancellable>()

    var onStartNavigation: ((MKRoute) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Init

    init(viewModel: RoutePreviewViewModel, mapViewController: MapViewController) {
        self.viewModel = viewModel
        self.mapViewController = mapViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapChild()
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

    private func setupMapChild() {
        addChild(mapViewController)
        view.addSubview(mapViewController.view)
        mapViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mapViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mapViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        mapViewController.didMove(toParent: self)
    }

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        view.addSubview(backButton)
        view.addSubview(bottomContainer)
        bottomContainer.addSubview(destinationLabel)
        bottomContainer.addSubview(favoriteButton)
        bottomContainer.addSubview(tableView)
        bottomContainer.addSubview(startButton)
        bottomContainer.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),

            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            destinationLabel.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: Theme.Spacing.xl),
            destinationLabel.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor, constant: Theme.Spacing.lg),
            destinationLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -Theme.Spacing.sm),

            favoriteButton.centerYAnchor.constraint(equalTo: destinationLabel.centerYAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor, constant: -Theme.Spacing.lg),
            favoriteButton.widthAnchor.constraint(equalToConstant: 40),
            favoriteButton.heightAnchor.constraint(equalToConstant: 40),

            tableView.topAnchor.constraint(equalTo: destinationLabel.bottomAnchor, constant: Theme.Spacing.md),
            tableView.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 180),

            startButton.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: Theme.Spacing.md),
            startButton.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor, constant: Theme.Spacing.lg),
            startButton.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor, constant: -Theme.Spacing.lg),
            startButton.heightAnchor.constraint(equalToConstant: 56),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.lg),

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
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        startButton.addTarget(self, action: #selector(startNavigationTapped), for: .touchUpInside)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.routes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] routes in
                guard let self else { return }
                tableView.reloadData()
                if !routes.isEmpty {
                    mapViewController.showRoutes(routes, selectedIndex: viewModel.selectedRouteIndex.value)
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
                    mapViewController.showRoutes(routes, selectedIndex: index)
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
                } else {
                    self?.loadingIndicator.stopAnimating()
                    self?.startButton.isEnabled = true
                    self?.startButton.alpha = 1.0
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

    @objc private func backTapped() {
        mapViewController.clearRoutes()
        mapViewController.clearDestination()
        onDismiss?()
    }

    @objc private func startNavigationTapped() {
        guard let selectedRoute = viewModel.getSelectedRoute() else { return }
        onStartNavigation?(selectedRoute)
    }

    @objc private func favoriteTapped() {
        viewModel.toggleFavorite()
    }
}

// MARK: - UITableViewDataSource

extension RoutePreviewViewController: UITableViewDataSource {

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

extension RoutePreviewViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.selectRoute(at: indexPath.row)
    }
}
