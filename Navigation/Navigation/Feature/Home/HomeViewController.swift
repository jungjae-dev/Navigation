import UIKit
import MapKit
import Combine

final class HomeViewController: UIViewController {

    // MARK: - Properties

    private var mapControlButtons: MapControlButtonsView!
    private(set) var mapControlBottomConstraint: NSLayoutConstraint!
    private var compassButton: MKCompassButton!

    private let viewModel: HomeViewModel
    let mapViewController: MapViewController
    let drawerManager = DrawerContainerManager()
    private var cancellables = Set<AnyCancellable>()

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
        setupCompassButton()
        setupMapControlButtons()
        setupDrawerContainer()
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

    private func setupMapControlButtons() {
        let buttons = MapControlButtonsView()
        self.mapControlButtons = buttons
        view.addSubview(buttons)

        mapControlBottomConstraint = buttons.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
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
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm
            ),
        ])
    }

    private func setupDrawerContainer() {
        drawerManager.install(in: self)
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

    // MARK: - Map Control Position (called by coordinator)

    func updateMapControlBottomOffset(_ height: CGFloat) {
        UIView.animate(withDuration: 0.3) {
            self.mapControlBottomConstraint.constant = -(height + Theme.Spacing.md)
            self.view.layoutIfNeeded()
        }
    }

    func updateMapInsets(top: CGFloat, bottom: CGFloat) {
        mapViewController.updateMapInsets(top: top, bottom: bottom)
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
