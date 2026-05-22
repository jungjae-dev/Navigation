import UIKit
import Combine

final class DevToolsViewController: UIViewController {

    // MARK: - Section & Row

    private enum Section: Int, CaseIterable {
        case gps = 0
        case recording = 1
        case files = 2
        case debug = 3
        case lbsProvider = 4
    }

    private enum LBSProviderRow: Int, CaseIterable {
        case searchProvider = 0
        case routeProvider = 1
    }

    private enum GPSRow: Int, CaseIterable {
        case locationType = 0
        case selectedFile = 1
    }

    private enum RecordingRow: Int, CaseIterable {
        case toggle = 0
        case status = 1
    }

    private enum FilesRow: Int, CaseIterable {
        case manageFiles = 0
    }

    private enum DebugRow: Int, CaseIterable {
        case overlay = 0
        case mapMatchVisualization = 1
        case predictiveDisplay = 2
    }

    // MARK: - UI

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        return tableView
    }()

    // MARK: - Properties

    private let viewModel: DevToolsViewModel
    private var cancellables = Set<AnyCancellable>()

    var onDismiss: (() -> Void)?
    var onShowFileList: (() -> Void)?
    var onSelectRecordingFile: (() -> Void)?

    // MARK: - Init

    init(viewModel: DevToolsViewModel) {
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
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        DevToolsSettings.shared.validateSelection()
        viewModel.refreshFileCount()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.title = "개발자 도구"

        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
        backButton.tintColor = Theme.Colors.label
        navigationItem.leftBarButtonItem = backButton

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DevToolsCell")
    }

    // MARK: - Binding

    private func bindViewModel() {
        Publishers.CombineLatest4(
            viewModel.recordingState,
            viewModel.recordingDuration,
            viewModel.recordingPointCount,
            viewModel.recordingDistance
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.tableView.reloadSections(IndexSet(integer: Section.recording.rawValue), with: .none)
        }
        .store(in: &cancellables)

        viewModel.gpxFileCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadSections(IndexSet(integer: Section.files.rawValue), with: .none)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(viewModel.searchProvider, viewModel.routeProvider)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.tableView.reloadSections(IndexSet(integer: Section.lbsProvider.rawValue), with: .none)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            viewModel.locationType,
            viewModel.selectedRecordingFileName
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.tableView.reloadSections(IndexSet(integer: Section.gps.rawValue), with: .none)
        }
        .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        onDismiss?()
    }

    @objc private func debugOverlaySwitchChanged(_ sender: UISwitch) {
        viewModel.setDebugOverlayEnabled(sender.isOn)
    }

    @objc private func mapMatchDebugSwitchChanged(_ sender: UISwitch) {
        DevToolsSettings.shared.setMapMatchDebugEnabled(sender.isOn)
    }

    @objc private func predictiveDisplaySwitchChanged(_ sender: UISwitch) {
        DevToolsSettings.shared.setPredictiveDisplayEnabled(sender.isOn)
    }

    @objc private func armSwitchChanged(_ sender: UISwitch) {
        let state = viewModel.recordingState.value
        // idle ↔ armed 만 토글 (recording/paused 상태에서는 호출되지 않음 — 셀이 스위치 미표시)
        if sender.isOn && state == .idle {
            viewModel.toggleRecording()
        } else if !sender.isOn && state == .armed {
            viewModel.toggleRecording()
        }
    }

    @objc private func locationTypeSegmentChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            viewModel.setLocationType(.real)
            return
        }
        // File 선택 — 유효한 파일이 이미 있으면 그대로 적용
        if DevToolsSettings.shared.selectedRecordingFileURL != nil {
            viewModel.setLocationType(.file)
            return
        }
        // 파일 없음 — 세그먼트는 Real로 즉시 되돌리고 picker 진입
        // 사용자가 picker에서 파일을 선택하면 그때 .file로 전환됨 (AppCoordinator.onSelectFile)
        sender.selectedSegmentIndex = 0
        onSelectRecordingFile?()
    }

    // MARK: - Helpers

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0fm", meters)
        }
        return String(format: "%.1fkm", meters / 1000)
    }
}

// MARK: - UITableViewDataSource

extension DevToolsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .gps:
            return GPSRow.allCases.count
        case .recording: return RecordingRow.allCases.count
        case .files: return FilesRow.allCases.count
        case .debug: return DebugRow.allCases.count
        case .lbsProvider: return LBSProviderRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .gps: return "GPS 소스"
        case .recording: return "녹화"
        case .files: return "파일 관리"
        case .debug: return "디버그"
        case .lbsProvider: return "위치 서비스"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DevToolsCell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        var config = cell.defaultContentConfiguration()
        config.textProperties.font = Theme.Table.cellFont
        config.textProperties.color = Theme.Table.cellColor
        config.secondaryTextProperties.font = Theme.Table.detailFont
        config.secondaryTextProperties.color = Theme.Table.detailColor

        guard let sec = Section(rawValue: indexPath.section) else { return cell }

        switch sec {
        case .gps:
            guard let row = GPSRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .locationType:
                config.text = "Location Type"
                config.image = UIImage(systemName: "location.circle")
                config.imageProperties.tintColor = Theme.Colors.primary

                let segmented = UISegmentedControl(items: ["Real", "File"])
                segmented.selectedSegmentIndex = viewModel.locationType.value == .real ? 0 : 1
                segmented.addTarget(self, action: #selector(locationTypeSegmentChanged), for: .valueChanged)
                cell.accessoryView = segmented
                cell.selectionStyle = .none

            case .selectedFile:
                config.text = "선택된 파일"
                config.image = UIImage(systemName: "doc.text")
                let isFileMode = viewModel.locationType.value == .file
                config.imageProperties.tintColor = isFileMode ? .systemOrange : Theme.Colors.secondaryLabel
                config.secondaryText = isFileMode
                    ? (viewModel.selectedRecordingFileName.value ?? "(파일 선택 필요)")
                    : "(File 모드에서만 사용)"
                config.textProperties.color = isFileMode ? Theme.Table.cellColor : Theme.Colors.secondaryLabel
                cell.accessoryType = isFileMode ? .disclosureIndicator : .none
                cell.selectionStyle = isFileMode ? .default : .none
            }

        case .recording:
            guard let row = RecordingRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .toggle:
                let state = viewModel.recordingState.value
                config.text = "1회 자동 녹화"
                config.image = UIImage(systemName: "record.circle")
                config.imageProperties.tintColor = Theme.Colors.destructive

                switch state {
                case .idle, .armed:
                    let toggle = UISwitch()
                    toggle.isOn = (state == .armed)
                    toggle.onTintColor = Theme.Colors.primary
                    toggle.addTarget(self, action: #selector(armSwitchChanged), for: .valueChanged)
                    cell.accessoryView = toggle
                    cell.selectionStyle = .none
                case .recording, .paused:
                    config.text = "녹화 중지"
                    config.image = UIImage(systemName: "stop.circle.fill")
                }

            case .status:
                let state = viewModel.recordingState.value
                switch state {
                case .idle:
                    config.text = "대기 중"
                    config.secondaryText = "다음 주행 시 자동으로 녹화됩니다 (1회)"
                    config.image = UIImage(systemName: "info.circle")
                    config.imageProperties.tintColor = Theme.Colors.secondaryLabel
                case .armed:
                    config.text = "녹화 대기 중"
                    config.secondaryText = "다음 주행 시작 시 자동 녹화"
                    config.image = UIImage(systemName: "circle.dotted")
                    config.imageProperties.tintColor = .systemOrange
                case .recording, .paused:
                    let duration = formattedDuration(viewModel.recordingDuration.value)
                    let points = viewModel.recordingPointCount.value
                    let distance = formattedDistance(viewModel.recordingDistance.value)
                    config.text = "\(duration) | \(points)개 포인트"
                    config.secondaryText = distance
                    config.image = UIImage(systemName: "location.fill")
                    config.imageProperties.tintColor = Theme.Colors.success
                }
                cell.selectionStyle = .none
            }

        case .files:
            guard let row = FilesRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .manageFiles:
                let count = viewModel.gpxFileCount.value
                config.text = "녹화 파일"
                config.secondaryText = "\(count)개"
                config.image = UIImage(systemName: "doc.text.fill")
                config.imageProperties.tintColor = .systemOrange
                cell.accessoryType = .disclosureIndicator
            }

        case .lbsProvider:
            guard let row = LBSProviderRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .searchProvider:
                config.text = "검색 제공자"
                config.secondaryText = viewModel.searchProvider.value.displayName
                config.image = UIImage(systemName: "magnifyingglass")
                config.imageProperties.tintColor = Theme.Colors.primary
                cell.accessoryType = .disclosureIndicator
            case .routeProvider:
                config.text = "경로 제공자"
                config.secondaryText = viewModel.routeProvider.value.displayName
                config.image = UIImage(systemName: "car.fill")
                config.imageProperties.tintColor = Theme.Colors.primary
                cell.accessoryType = .disclosureIndicator
            }

        case .debug:
            guard let row = DebugRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .overlay:
                config.text = "디버그 오버레이"
                config.image = UIImage(systemName: "ladybug.fill")
                config.imageProperties.tintColor = .systemGreen

                let toggle = UISwitch()
                toggle.isOn = viewModel.debugOverlayEnabled.value
                toggle.onTintColor = Theme.Colors.primary
                toggle.addTarget(self, action: #selector(debugOverlaySwitchChanged), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none

            case .mapMatchVisualization:
                config.text = "맵매칭 시각화"
                config.secondaryText = "GPS(빨강) ↔ 매칭 위치(파랑) 화살표 표시"
                config.image = UIImage(systemName: "scope")
                config.imageProperties.tintColor = .systemPurple

                let toggle = UISwitch()
                toggle.isOn = DevToolsSettings.shared.mapMatchDebugEnabled.value
                toggle.onTintColor = Theme.Colors.primary
                toggle.addTarget(self, action: #selector(mapMatchDebugSwitchChanged), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none

            case .predictiveDisplay:
                config.text = "1초 예측 표시"
                config.secondaryText = "매칭 위치에서 1초 앞을 예측해 아이콘 위치로 사용"
                config.image = UIImage(systemName: "arrow.forward.circle")
                config.imageProperties.tintColor = .systemBlue

                let toggle = UISwitch()
                toggle.isOn = DevToolsSettings.shared.predictiveDisplayEnabled.value
                toggle.onTintColor = Theme.Colors.primary
                toggle.addTarget(self, action: #selector(predictiveDisplaySwitchChanged), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            }
        }

        cell.contentConfiguration = config
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DevToolsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let sec = Section(rawValue: indexPath.section) else { return }

        switch sec {
        case .gps:
            guard let row = GPSRow(rawValue: indexPath.row) else { return }
            if row == .selectedFile, viewModel.locationType.value == .file {
                onSelectRecordingFile?()
            }

        case .recording:
            guard let row = RecordingRow(rawValue: indexPath.row) else { return }
            // idle/armed: 스위치로만 조작. recording/paused에서만 셀 탭으로 정지
            if row == .toggle {
                let state = viewModel.recordingState.value
                if state == .recording || state == .paused {
                    viewModel.toggleRecording()
                }
            }

        case .files:
            guard let row = FilesRow(rawValue: indexPath.row) else { return }
            if row == .manageFiles {
                onShowFileList?()
            }

        case .debug:
            break

        case .lbsProvider:
            guard let row = LBSProviderRow(rawValue: indexPath.row) else { return }
            switch row {
            case .searchProvider: showSearchProviderPicker()
            case .routeProvider: showRouteProviderPicker()
            }
        }
    }
}

// MARK: - LBS Provider Pickers

private extension DevToolsViewController {

    func showSearchProviderPicker() {
        let alert = UIAlertController(title: "검색 제공자", message: nil, preferredStyle: .actionSheet)
        for provider in LBSProviderType.allCases {
            let action = UIAlertAction(title: provider.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setSearchProvider(provider)
            }
            if provider == viewModel.searchProvider.value {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    func showRouteProviderPicker() {
        let alert = UIAlertController(title: "경로 제공자", message: nil, preferredStyle: .actionSheet)
        for provider in LBSProviderType.allCases {
            let action = UIAlertAction(title: provider.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setRouteProvider(provider)
            }
            if provider == viewModel.routeProvider.value {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }
}
