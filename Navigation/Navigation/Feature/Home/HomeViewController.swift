import UIKit
import MapKit
import Combine

final class HomeViewController: UIViewController {

    // MARK: - Properties

    private var mapControlButtons: MapControlButtonsView!
    private(set) var mapControlBottomConstraint: NSLayoutConstraint!
    private var compassButton: MKCompassButton!
    private var layerButtons: MapLayerButtonsView!   // 좌측 데이터 레이어 (따릉이·버스·혼잡)
    /// 애플 지도 로고·법적표기 위로 버튼을 띄우는 하단 여백
    private let mapAttributionClearance: CGFloat = 28

    private let viewModel: HomeViewModel
    private let bikeViewModel = BikeViewModel()
    private let busViewModel = BusViewModel()
    let mapViewController: MapViewController
    let drawerManager = DrawerContainerManager()
    private var cancellables = Set<AnyCancellable>()

    // 실시간 혼잡(Live Pulse) — citydata 라이브 면색칠 + 예측 슬라이더
    private let hotspotCatalog = HotspotCatalog(bundle: .main)
    private lazy var citydataService = hotspotCatalog.map { CitydataService(catalog: $0) }
    private var isLivePulseOn = false
    private var livePulsePanel: UIView?
    private weak var livePulseLabel: UILabel?
    private var livePulsePlaces: [String: CongestionPlace] = [:]
    private var livePulseOffset = 0

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
        setupLayerButtons()
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
            constant: -(200 + Theme.Spacing.md + mapAttributionClearance)
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

    /// 좌측 데이터 레이어 버튼 (따릉이·버스 = 오버레이 | 실시간 혼잡 = 모드).
    /// 우측 지도조작 버튼과 세로 위치를 맞춤(bottom 동기).
    private func setupLayerButtons() {
        let bar = MapLayerButtonsView()
        self.layerButtons = bar
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            bar.bottomAnchor.constraint(equalTo: mapControlButtons.bottomAnchor),
        ])
        bar.onBike = { [weak self] in
            Task {
                guard let self else { return }
                await self.bikeViewModel.toggleLayer()
                // 켤 때 현재 줌이 정류소 표출 레벨보다 멀면 보이는 레벨로 확대 (중심 유지)
                if self.bikeViewModel.isLayerOn { self.mapViewController.zoomToShowBikeStations() }
            }
        }
        bar.onBus = { [weak self] in
            guard let self else { return }
            self.busViewModel.toggleLayer()
            if self.busViewModel.isLayerOn { self.mapViewController.zoomToShowBusStops() }
        }
        bar.onCongestion = { [weak self] in self?.toggleLivePulse() }
        bar.onBikeRefresh = { [weak self] in self?.handleBikeRefreshTapped() }

        // 따릉이 레이어 ON/OFF → 버튼 상태 + 지도 마커 동기화
        bikeViewModel.$isLayerOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOn in
                guard let self else { return }
                self.layerButtons.setBike(on: isOn)
                if isOn {
                    self.mapViewController.setBikeStations(BikeStationCache.shared.stations.value)
                } else {
                    self.mapViewController.clearBikeStations()
                }
            }
            .store(in: &cancellables)

        // 캐시 변경 시 마커 동기화 (레이어 ON 일 때만)
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
                self.layerButtons.setBus(on: isOn)
            }
            .store(in: &cancellables)

        // 따릉이 정류소 마커 탭은 AppCoordinator 가 직접 mapViewController.onBikeStationSelected 처리
    }

    // MARK: - Live Pulse (실시간 혼잡)

    private func toggleLivePulse() {
        isLivePulseOn.toggle()
        layerButtons.setCongestion(on: isLivePulseOn)

        guard isLivePulseOn else {
            mapViewController.clearCongestion()
            hideLivePulseSlider()
            restoreOverlayLayers()   // 따릉이·버스 복원
            livePulsePlaces.removeAll()
            return
        }
        guard let service = citydataService, let catalog = hotspotCatalog else {
            isLivePulseOn = false
            layerButtons.setCongestion(on: false)
            return
        }
        hideOverlayLayers()          // 진입 시 겹치는 POI 레이어 임시 OFF (배타)
        mapViewController.clearCongestion()
        livePulsePlaces.removeAll()
        livePulseOffset = 0
        showLivePulseSlider()

        // 121곳 고정 소집합 → 전체 로드(5분 캐시). 배치 도착마다 점진 렌더링(빈 화면 방지).
        let allNames = catalog.hotspots.map(\.areaName)
        let total = allNames.count
        let fit = catalog.visibleAreaNames(in: mapViewController.mapView.visibleMapRect).isEmpty
        livePulseLabel?.text = "불러오는 중 0/\(total)…"

        Task { [weak self] in
            _ = await service.fetch(areaNames: allNames, maxConcurrent: 15, onBatch: { [weak self] batch in
                guard let self, self.isLivePulseOn else { return }
                for p in batch { self.livePulsePlaces[p.areaName] = p }
                self.mapViewController.addCongestion(batch)
                self.livePulseLabel?.text = "불러오는 중 \(self.livePulsePlaces.count)/\(total)…"
            })
            guard let self, self.isLivePulseOn else { return }
            if fit { self.mapViewController.fitCongestion() }
            if self.livePulsePlaces.isEmpty {
                self.livePulseLabel?.text = "실시간 데이터를 불러올 수 없어요 · 다시 시도"  // FR-012
            } else {
                self.updateLivePulseLabel(offset: self.livePulseOffset)  // 기준시각(FR-003)
            }
        }
    }

    /// 진입 시 겹치는 POI 레이어(따릉이·버스) 시각적 임시 숨김 (토글 설정값은 보존, FR-008)
    private func hideOverlayLayers() {
        mapViewController.clearBikeStations()
        mapViewController.clearBusStops()
    }

    /// 종료 시 레이어 설정대로 복원
    private func restoreOverlayLayers() {
        if bikeViewModel.isLayerOn {
            mapViewController.setBikeStations(BikeStationCache.shared.stations.value)
        }
        if busViewModel.isLayerOn {
            mapViewController.setBusStops(busViewModel.busStopsPublisher.value)
        }
    }

    // MARK: - Live Pulse 예측 슬라이더 (지금→+12h)

    private func showLivePulseSlider() {
        guard livePulsePanel == nil else { return }
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = Theme.Card.backgroundColor.withAlphaComponent(0.95)
        panel.layer.cornerRadius = Theme.Card.cornerRadius
        panel.layer.shadowColor = Theme.Shadow.color
        panel.layer.shadowOpacity = Theme.Shadow.opacity
        panel.layer.shadowOffset = Theme.Shadow.offset
        panel.layer.shadowRadius = Theme.Shadow.radius

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center

        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 12
        slider.value = 0
        slider.minimumTrackTintColor = Theme.Colors.primary
        slider.addTarget(self, action: #selector(livePulseOffsetChanged(_:)), for: .valueChanged)

        // 시각 눈금 (지금 → +12h를 실제 시각으로) — 직관성
        let ticks = UIStackView()
        ticks.translatesAutoresizingMaskIntoConstraints = false
        ticks.axis = .horizontal
        ticks.distribution = .equalSpacing
        let nowHour = Calendar.current.component(.hour, from: Date())
        for offset in [0, 4, 8, 12] {   // 4곳 — AM/PM 표기 공간 확보
            let t = UILabel()
            t.font = .systemFont(ofSize: 12, weight: .semibold)
            t.textColor = .label
            t.text = offset == 0 ? "지금" : Self.koreanHour((nowHour + offset) % 24)
            ticks.addArrangedSubview(t)
        }

        panel.addSubview(label)
        panel.addSubview(slider)
        panel.addSubview(ticks)
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            label.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),

            slider.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            slider.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),

            // 눈금은 슬라이더 트랙 폭에 맞춰 (thumb 반경 고려해 살짝 안쪽)
            ticks.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            ticks.leadingAnchor.constraint(equalTo: slider.leadingAnchor, constant: 4),
            ticks.trailingAnchor.constraint(equalTo: slider.trailingAnchor, constant: -4),
            ticks.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
        ])

        livePulsePanel = panel
        livePulseLabel = label
        updateLivePulseLabel(offset: 0)
    }

    private func hideLivePulseSlider() {
        livePulsePanel?.removeFromSuperview()
        livePulsePanel = nil
    }

    @objc private func livePulseOffsetChanged(_ slider: UISlider) {
        let offset = Int(slider.value.rounded())
        slider.value = Float(offset)  // 정수 스냅
        livePulseOffset = offset
        updateLivePulseLabel(offset: offset)
        mapViewController.updateCongestion(offset: offset)
    }

    private func updateLivePulseLabel(offset: Int) {
        let hour = (Calendar.current.component(.hour, from: Date()) + offset) % 24
        livePulseLabel?.text = offset == 0 ? "지금 \(Self.koreanHour(hour))" : "\(Self.koreanHour(hour)) 예측"
    }

    /// 24시 → "오전/오후 N시" (0시=오전 12시, 12시=오후 12시)
    private static func koreanHour(_ h: Int) -> String {
        let period = h < 12 ? "오전" : "오후"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(period) \(h12)시"
    }

    private func handleBikeRefreshTapped() {
        layerButtons.setBikeRefreshing(true)
        Task { [weak self] in
            await self?.bikeViewModel.fetchAll()
            self?.layerButtons.setBikeRefreshing(false)
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
            self.mapControlBottomConstraint.constant = -(height + Theme.Spacing.md + self.mapAttributionClearance)
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
