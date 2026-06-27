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
    private let busViewModel = BusViewModel()
    let mapViewController: MapViewController
    let drawerManager = DrawerContainerManager()
    private var cancellables = Set<AnyCancellable>()

    // 실시간 혼잡(Live Pulse) — citydata 라이브 마커 (MVP 슬라이스: 토글 ON → 가시영역 혼잡 마커)
    private let hotspotCatalog = HotspotCatalog(bundle: .main)
    private lazy var citydataService = hotspotCatalog.map { CitydataService(catalog: $0) }
    private var isLivePulseOn = false

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
        Task { await TransitDataService.shared.load() }
        // 저장된 레이어 상태 복원 (따릉이 ON 이면 데이터 확보)
        Task { await bikeViewModel.restoreLayerIfNeeded() }
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
        buttons.onBikeRefreshTapped = { [weak self] in
            self?.handleBikeRefreshTapped()
        }
        buttons.onPOILayerTapped = { [weak self] in
            self?.handlePOILayerTapped()
        }
        buttons.onLivePulseTapped = { [weak self] in
            self?.toggleLivePulse()
        }

        mapViewController.onTrackingModeChanged = { [weak self] mode in
            self?.mapControlButtons.updateCurrentLocationIcon(for: mode)
        }

        // 따릉이 레이어 ON/OFF → 버튼 시각 상태 갱신 + 지도 마커 동기화
        bikeViewModel.$isLayerOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in
                guard let self else { return }
                self.mapControlButtons.updateBikeLayerState(isOn: isOn)
                if isOn {
                    // 캐시에 데이터가 있으면 즉시 마커 표시 (재 fetch 안 함)
                    self.mapViewController.setBikeStations(BikeStationCache.shared.stations.value)
                } else {
                    self.mapViewController.clearBikeStations()
                }
            }
            .store(in: &cancellables)

        // 캐시 변경 시 마커 동기화 (단, 레이어 ON 일 때만)
        BikeStationCache.shared.stations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stations in
                guard let self, self.bikeViewModel.isLayerOn else { return }
                self.mapViewController.setBikeStations(stations)
            }
            .store(in: &cancellables)

        // 버스 레이어 ON/OFF
        busViewModel.isLayerOnPublisher
            .receive(on: DispatchQueue.main)
            .combineLatest(busViewModel.busStopsPublisher)
            .sink { [weak self] isOn, stops in
                guard let self else { return }
                if isOn { self.mapViewController.setBusStops(stops) }
                else { self.mapViewController.clearBusStops() }
                self.updatePOIButtonState()
            }
            .store(in: &cancellables)

        // 따릉이 정류소 마커 탭은 AppCoordinator 가 직접 mapViewController.onBikeStationSelected 처리
    }

    private func updatePOIButtonState() {
        let hasActive = bikeViewModel.isLayerOn || busViewModel.isLayerOn
        mapControlButtons.updatePOILayerState(hasActiveLayer: hasActive)
    }

    // MARK: - Live Pulse (실시간 혼잡)

    private func toggleLivePulse() {
        isLivePulseOn.toggle()
        mapControlButtons.updateLivePulseState(isOn: isLivePulseOn)
        print("[LivePulse] toggle → on=\(isLivePulseOn), catalog=\(hotspotCatalog != nil), service=\(citydataService != nil)")

        guard isLivePulseOn else {
            mapViewController.clearCongestion()
            return
        }
        guard let service = citydataService else {
            print("[LivePulse] ✗ 카탈로그/서비스 nil — hotspots.json 번들 누락 의심")
            isLivePulseOn = false
            mapControlButtons.updateLivePulseState(isOn: false)
            return
        }
        let rect = mapViewController.mapView.visibleMapRect
        let center = mapViewController.mapView.region.center
        print("[LivePulse] 지도 중심=(\(String(format: "%.4f", center.latitude)), \(String(format: "%.4f", center.longitude)))")

        var names = hotspotCatalog?.visibleAreaNames(in: rect) ?? []
        var shouldFit = false
        if names.isEmpty {
            // 가시영역에 핫스팟 없음(지도가 서울 도심 밖) → 전체 시드 로드 + 카메라 맞춤
            names = hotspotCatalog?.hotspots.map(\.areaName) ?? []
            shouldFit = true
            print("[LivePulse] 가시영역 0곳 → 전체 \(names.count)곳 로드 + 카메라 맞춤")
        } else {
            print("[LivePulse] 가시영역 핫스팟 \(names.count)곳: \(names)")
        }

        Task { [weak self] in
            let places = await service.fetch(areaNames: names)
            print("[LivePulse] fetch 완료 places=\(places.count) levels=\(places.map { $0.liveLevel.displayName })")
            guard let self, self.isLivePulseOn else { return }
            self.mapViewController.setCongestion(places)
            if shouldFit { self.mapViewController.fitCongestion() }
            print("[LivePulse] setCongestion 적용 (마커 \(places.filter { $0.liveLevel.isDisplayable }.count)개)")
        }
    }

    private func handlePOILayerTapped() {
        let alert = UIAlertController(title: "지도 레이어", message: nil, preferredStyle: .actionSheet)

        let bikeTitle = bikeViewModel.isLayerOn ? "✓ 따릉이" : "따릉이"
        alert.addAction(UIAlertAction(title: bikeTitle, style: .default) { [weak self] _ in
            Task { await self?.bikeViewModel.toggleLayer() }
        })

        let busTitle = busViewModel.isLayerOn ? "✓ 버스 정류소" : "버스 정류소"
        alert.addAction(UIAlertAction(title: busTitle, style: .default) { [weak self] _ in
            self?.busViewModel.toggleLayer()
        })

        alert.addAction(UIAlertAction(title: "닫기", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = mapControlButtons
            popover.sourceRect = mapControlButtons.bounds
        }
        present(alert, animated: true)
    }

    private func handleBikeRefreshTapped() {
        mapControlButtons.setBikeRefreshing(true)
        Task { [weak self] in
            await self?.bikeViewModel.fetchAll()
            self?.mapControlButtons.setBikeRefreshing(false)
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
