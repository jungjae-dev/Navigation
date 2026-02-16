import UIKit
import Combine

final class DevToolsViewController: UIViewController {

    // MARK: - Section & Row

    private enum Section: Int, CaseIterable {
        case recording = 0
        case playback = 1
        case files = 2
        case debug = 3
    }

    private enum RecordingRow: Int, CaseIterable {
        case toggle = 0
        case status = 1
    }

    private enum PlaybackRow: Int, CaseIterable {
        case selectFile = 0
    }

    private enum FilesRow: Int, CaseIterable {
        case manageFiles = 0
    }

    private enum DebugRow: Int, CaseIterable {
        case overlay = 0
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
    var onSelectFileForPlayback: (() -> Void)?

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
        viewModel.refreshFileCount()
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
    }

    // MARK: - Actions

    @objc private func backTapped() {
        onDismiss?()
    }

    @objc private func debugOverlaySwitchChanged(_ sender: UISwitch) {
        viewModel.setDebugOverlayEnabled(sender.isOn)
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
        case .recording: return RecordingRow.allCases.count
        case .playback: return PlaybackRow.allCases.count
        case .files: return FilesRow.allCases.count
        case .debug: return DebugRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .recording: return "GPX 녹화"
        case .playback: return "GPX 재생"
        case .files: return "파일 관리"
        case .debug: return "디버그"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DevToolsCell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        var config = cell.defaultContentConfiguration()

        guard let sec = Section(rawValue: indexPath.section) else { return cell }

        switch sec {
        case .recording:
            guard let row = RecordingRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .toggle:
                let state = viewModel.recordingState.value
                switch state {
                case .idle:
                    config.text = "녹화 시작"
                    config.image = UIImage(systemName: "record.circle")
                    config.imageProperties.tintColor = Theme.Colors.destructive
                case .recording:
                    config.text = "녹화 중지"
                    config.image = UIImage(systemName: "stop.circle.fill")
                    config.imageProperties.tintColor = Theme.Colors.destructive
                case .paused:
                    config.text = "녹화 재개"
                    config.image = UIImage(systemName: "play.circle.fill")
                    config.imageProperties.tintColor = .systemOrange
                }

            case .status:
                let state = viewModel.recordingState.value
                if state == .idle {
                    config.text = "대기 중"
                    config.secondaryText = "GPS 위치를 녹화하여 GPX 파일로 저장합니다"
                    config.image = UIImage(systemName: "info.circle")
                    config.imageProperties.tintColor = Theme.Colors.secondaryLabel
                } else {
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

        case .playback:
            guard let row = PlaybackRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .selectFile:
                config.text = "GPX 파일 재생"
                config.secondaryText = "녹화된 파일을 선택하여 재생합니다"
                config.image = UIImage(systemName: "play.circle")
                config.imageProperties.tintColor = Theme.Colors.primary
                cell.accessoryType = .disclosureIndicator
            }

        case .files:
            guard let row = FilesRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .manageFiles:
                let count = viewModel.gpxFileCount.value
                config.text = "GPX 파일"
                config.secondaryText = "\(count)개"
                config.image = UIImage(systemName: "doc.text.fill")
                config.imageProperties.tintColor = .systemOrange
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
        case .recording:
            guard let row = RecordingRow(rawValue: indexPath.row) else { return }
            if row == .toggle {
                viewModel.toggleRecording()
            }

        case .playback:
            guard let row = PlaybackRow(rawValue: indexPath.row) else { return }
            if row == .selectFile {
                onSelectFileForPlayback?()
            }

        case .files:
            guard let row = FilesRow(rawValue: indexPath.row) else { return }
            if row == .manageFiles {
                onShowFileList?()
            }

        case .debug:
            break
        }
    }
}
