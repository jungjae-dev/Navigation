import UIKit
import MapKit
import Combine

final class HomeViewController: UIViewController {

    // MARK: - Properties

    private var mapControlButtons: MapControlButtonsView!
    private(set) var mapControlBottomConstraint: NSLayoutConstraint!
    private var compassButton: MKCompassButton!

    private let viewModel: HomeViewModel
    private let bikeViewModel = BikeViewModel()
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
        setupLBSNotifications()
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
        buttons.onBikeLayerTapped = { [weak self] in
            self?.handleBikeLayerTapped()
        }

        mapViewController.onTrackingModeChanged = { [weak self] mode in
            self?.mapControlButtons.updateCurrentLocationIcon(for: mode)
        }

        // 따릉이 레이어 ON/OFF → 버튼 시각 상태 갱신
        bikeViewModel.$isLayerOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in
                self?.mapControlButtons.updateBikeLayerState(isOn: isOn)
            }
            .store(in: &cancellables)
    }

    private func handleBikeLayerTapped() {
        Task { await bikeViewModel.toggleLayer() }
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

    // MARK: - LBS Notifications

    private func setupLBSNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSearchQuotaExceeded),
            name: .lbsSearchQuotaExceeded,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteFallback),
            name: .lbsRouteFallbackActivated,
            object: nil
        )
    }

    @objc private func handleSearchQuotaExceeded() {
        DispatchQueue.main.async { [weak self] in
            self?.showLBSAlert(
                title: "검색 한도 초과",
                message: "오늘 카카오 검색 한도에 도달했습니다.\n내일 자정에 자동으로 초기화됩니다."
            )
        }
    }

    @objc private func handleRouteFallback() {
        guard LBSServiceProvider.shared.routeProviderType == .kakao else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showLBSAlert(
                title: "경로 서비스 일시 제한",
                message: "카카오 경로 서비스가 일시적으로 제한됩니다.\n잠시 후 자동으로 복구됩니다."
            )
        }
    }

    private func showLBSAlert(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
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
