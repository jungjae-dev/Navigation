import UIKit
import MapKit
import Combine

final class HomeViewController: UIViewController {

    // MARK: - UI Components

    private let searchBarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.secondaryBackground
        view.layer.cornerRadius = Theme.CornerRadius.medium
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = Theme.Shadow.offset
        view.layer.shadowRadius = Theme.Shadow.radius
        return view
    }()

    private let searchIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "magnifyingglass")
        imageView.tintColor = Theme.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let searchLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "여기서 검색"
        label.font = Theme.Fonts.body
        label.textColor = Theme.Colors.secondaryLabel
        return label
    }()

    private let settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "gearshape.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        button.backgroundColor = Theme.Colors.secondaryBackground
        button.layer.cornerRadius = 24
        button.layer.shadowColor = Theme.Shadow.color
        button.layer.shadowOpacity = Theme.Shadow.opacity
        button.layer.shadowOffset = Theme.Shadow.offset
        button.layer.shadowRadius = Theme.Shadow.radius
        return button
    }()

    // MARK: - Properties

    private var mapControlButtons: MapControlButtonsView!
    private var mapControlBottomConstraint: NSLayoutConstraint!
    private var compassButton: MKCompassButton!

    private let viewModel: HomeViewModel
    private let mapViewController: MapViewController
    private var cancellables = Set<AnyCancellable>()
    private var homeDrawer: HomeDrawerViewController!

    var onSearchBarTapped: (() -> Void)?
    var onFavoriteTapped: ((FavoritePlace) -> Void)?
    var onRecentSearchTapped: ((SearchHistory) -> Void)?
    var onSettingsTapped: (() -> Void)?

    // MARK: - Init

    init(viewModel: HomeViewModel, mapViewController: MapViewController) {
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
        setupSearchBar()
        setupSettingsButton()
        setupCompassButton()
        setupMapControlButtons()
        setupDrawer()
        setupAccessibility()
        bindViewModel()
        handleInitialPermission()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadHomeData()
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

    private func setupSearchBar() {
        view.addSubview(settingsButton)
        view.addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIcon)
        searchBarContainer.addSubview(searchLabel)

        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm
            ),
            settingsButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg
            ),
            settingsButton.widthAnchor.constraint(equalToConstant: 48),
            settingsButton.heightAnchor.constraint(equalToConstant: 48),

            searchBarContainer.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm
            ),
            searchBarContainer.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.lg
            ),
            searchBarContainer.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor, constant: -Theme.Spacing.sm
            ),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 48),

            searchIcon.leadingAnchor.constraint(
                equalTo: searchBarContainer.leadingAnchor, constant: Theme.Spacing.md
            ),
            searchIcon.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20),

            searchLabel.leadingAnchor.constraint(
                equalTo: searchIcon.trailingAnchor, constant: Theme.Spacing.sm
            ),
            searchLabel.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchLabel.trailingAnchor.constraint(
                equalTo: searchBarContainer.trailingAnchor, constant: -Theme.Spacing.md
            ),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(searchBarTapped))
        searchBarContainer.addGestureRecognizer(tapGesture)
        searchBarContainer.isUserInteractionEnabled = true
    }

    private func setupSettingsButton() {
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
    }

    private func setupMapControlButtons() {
        let buttons = MapControlButtonsView()
        self.mapControlButtons = buttons
        view.addSubview(buttons)

        mapControlBottomConstraint = buttons.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -(200 + Theme.Spacing.md)
        )

        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg
            ),
            mapControlBottomConstraint,
        ])

        buttons.onCurrentLocationTapped = { [weak self] in
            self?.handleCurrentLocationTapped()
        }
        buttons.onMapModeTapped = { [weak self] in
            self?.handleMapModeTapped()
        }

        mapViewController.onTrackingModeChanged = { [weak self] mode in
            self?.mapControlButtons.updateCurrentLocationIcon(for: mode)
        }
    }

    private func setupCompassButton() {
        let compass = MKCompassButton(mapView: mapViewController.mapView)
        compass.translatesAutoresizingMaskIntoConstraints = false
        compass.compassVisibility = .adaptive
        self.compassButton = compass
        view.addSubview(compass)

        NSLayoutConstraint.activate([
            compass.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.lg
            ),
            compass.topAnchor.constraint(
                equalTo: searchBarContainer.bottomAnchor, constant: Theme.Spacing.sm
            ),
        ])
    }

    private func setupDrawer() {
        let drawer = HomeDrawerViewController(viewModel: viewModel)
        self.homeDrawer = drawer
        drawer.onFavoriteTapped = { [weak self] fav in self?.onFavoriteTapped?(fav) }
        drawer.onRecentSearchTapped = { [weak self] h in self?.onRecentSearchTapped?(h) }

        addChild(drawer)
        view.addSubview(drawer.view)
        drawer.view.translatesAutoresizingMaskIntoConstraints = false

        let heightConstraint = drawer.view.heightAnchor.constraint(equalToConstant: 200)
        drawer.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            drawer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,
        ])

        drawer.didMove(toParent: self)

        drawer.onDetentChanged = { [weak self] detent in
            self?.updateMapControlPosition(for: detent)
        }
        drawer.onHeightChanged = { [weak self] height in
            self?.updateMapControlPositionDuringPan(height: height)
        }
    }

    // MARK: - Accessibility

    private func setupAccessibility() {
        searchBarContainer.isAccessibilityElement = true
        searchBarContainer.accessibilityLabel = "검색"
        searchBarContainer.accessibilityHint = "탭하여 장소를 검색합니다"
        searchBarContainer.accessibilityTraits = .searchField

        settingsButton.accessibilityLabel = "설정"
        settingsButton.accessibilityHint = "앱 설정을 엽니다"
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.authStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleAuthStatusChange(status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Map Control Actions

    private func handleCurrentLocationTapped() {
        let newMode = mapViewController.cycleUserTrackingMode()
        mapControlButtons.updateCurrentLocationIcon(for: newMode)
    }

    private func handleMapModeTapped() {
        let isSatellite = mapViewController.cycleMapType()
        mapControlButtons.updateMapModeIcon(isSatellite: isSatellite)
    }

    // MARK: - Drawer Position Tracking

    private func updateMapControlPosition(for detent: HomeDrawerViewController.DrawerDetent) {
        let drawerHeight: CGFloat = switch detent {
        case .small, .medium:
            detent.height(in: view)
        case .large:
            HomeDrawerViewController.DrawerDetent.medium.height(in: view)
        }

        UIView.animate(
            withDuration: 0.35, delay: 0,
            usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5,
            options: .curveEaseInOut
        ) {
            self.mapControlBottomConstraint.constant = -(drawerHeight + Theme.Spacing.md)
            self.view.layoutIfNeeded()
        }
    }

    private func updateMapControlPositionDuringPan(height: CGFloat) {
        let mediumHeight = HomeDrawerViewController.DrawerDetent.medium.height(in: view)
        let effectiveHeight = min(height, mediumHeight)
        mapControlBottomConstraint.constant = -(effectiveHeight + Theme.Spacing.md)
    }

    // MARK: - Actions

    @objc private func searchBarTapped() {
        onSearchBarTapped?()
    }

    @objc private func settingsTapped() {
        onSettingsTapped?()
    }

    // MARK: - Permission Handling

    private func handleInitialPermission() {
        let status = viewModel.authStatus.value
        if status == .notDetermined {
            viewModel.requestLocationPermission()
        } else if status.isAuthorized {
            viewModel.startLocationUpdates()
        }
    }

    private func handleAuthStatusChange(_ status: LocationAuthStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            viewModel.startLocationUpdates()

        case .denied, .restricted:
            showLocationDeniedAlert()

        case .notDetermined:
            break
        }
    }

    private func showLocationDeniedAlert() {
        let alert = UIAlertController(
            title: "위치 권한 필요",
            message: "지도에 현재 위치를 표시하려면 위치 권한이 필요합니다. 설정에서 위치 권한을 허용해주세요.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "설정으로 이동", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))

        present(alert, animated: true)
    }
}
