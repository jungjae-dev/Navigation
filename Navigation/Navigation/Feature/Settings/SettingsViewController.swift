import UIKit
import Combine

final class SettingsViewController: UIViewController {

    // MARK: - Section & Row

    private enum Section: Int, CaseIterable {
        case voice = 0
        case map = 1
        case data = 2
        case info = 3
    }

    private enum VoiceRow: Int, CaseIterable {
        case enabled = 0
        case speed = 1
    }

    private enum MapRow: Int, CaseIterable {
        case type = 0
    }

    private enum DataRow: Int, CaseIterable {
        case favorites = 0
        case clearHistory = 1
    }

    private enum InfoRow: Int, CaseIterable {
        case version = 0
    }

    // MARK: - UI Components

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        return tableView
    }()

    // MARK: - Properties

    private let viewModel: SettingsViewModel
    private var cancellables = Set<AnyCancellable>()

    var onDismiss: (() -> Void)?

    // MARK: - Init

    init(viewModel: SettingsViewModel) {
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
        viewModel.refreshDataCounts()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        // Navigation bar style
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.title = "설정"

        // Back button
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
    }

    // MARK: - Binding

    private func bindViewModel() {
        Publishers.CombineLatest3(
            viewModel.voiceEnabled,
            viewModel.voiceSpeed,
            viewModel.mapType
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.tableView.reloadData()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            viewModel.favoriteCount,
            viewModel.searchHistoryCount
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.tableView.reloadData()
        }
        .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        onDismiss?()
    }

    @objc private func voiceSwitchChanged(_ sender: UISwitch) {
        viewModel.setVoiceEnabled(sender.isOn)
    }

    private func showVoiceSpeedPicker() {
        let alert = UIAlertController(title: "음성 속도", message: nil, preferredStyle: .actionSheet)

        for speed in SettingsViewModel.VoiceSpeed.allCases {
            let action = UIAlertAction(title: speed.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setVoiceSpeed(speed)
            }
            if speed == viewModel.voiceSpeed.value {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    private func showMapTypePicker() {
        let alert = UIAlertController(title: "지도 유형", message: nil, preferredStyle: .actionSheet)

        for mapType in SettingsViewModel.MapTypeOption.allCases {
            let action = UIAlertAction(title: mapType.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setMapType(mapType)
            }
            if mapType == viewModel.mapType.value {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    private func confirmClearSearchHistory() {
        let alert = UIAlertController(
            title: "검색 기록 삭제",
            message: "모든 검색 기록을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            self?.viewModel.clearSearchHistory()
        })

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))

        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .voice: return VoiceRow.allCases.count
        case .map: return MapRow.allCases.count
        case .data: return DataRow.allCases.count
        case .info: return InfoRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .voice: return "음성 안내"
        case .map: return "지도"
        case .data: return "데이터"
        case .info: return "정보"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        var config = cell.defaultContentConfiguration()

        guard let sec = Section(rawValue: indexPath.section) else { return cell }

        switch sec {
        case .voice:
            guard let row = VoiceRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .enabled:
                config.text = "음성 안내"
                config.image = UIImage(systemName: "speaker.wave.2.fill")
                config.imageProperties.tintColor = Theme.Colors.primary

                let toggle = UISwitch()
                toggle.isOn = viewModel.voiceEnabled.value
                toggle.onTintColor = Theme.Colors.primary
                toggle.addTarget(self, action: #selector(voiceSwitchChanged), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none

            case .speed:
                config.text = "음성 속도"
                config.secondaryText = viewModel.voiceSpeed.value.displayName
                config.image = UIImage(systemName: "gauge.with.dots.needle.33percent")
                config.imageProperties.tintColor = Theme.Colors.primary
                cell.accessoryType = .disclosureIndicator
            }

        case .map:
            guard let row = MapRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .type:
                config.text = "지도 유형"
                config.secondaryText = viewModel.mapType.value.displayName
                config.image = UIImage(systemName: "map.fill")
                config.imageProperties.tintColor = Theme.Colors.success
                cell.accessoryType = .disclosureIndicator
            }

        case .data:
            guard let row = DataRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .favorites:
                config.text = "즐겨찾기"
                config.secondaryText = "\(viewModel.favoriteCount.value)개"
                config.image = UIImage(systemName: "star.fill")
                config.imageProperties.tintColor = .systemYellow
                cell.selectionStyle = .none

            case .clearHistory:
                config.text = "검색 기록 삭제"
                config.secondaryText = "\(viewModel.searchHistoryCount.value)개"
                config.image = UIImage(systemName: "trash.fill")
                config.imageProperties.tintColor = Theme.Colors.destructive
                config.textProperties.color = Theme.Colors.destructive
            }

        case .info:
            guard let row = InfoRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .version:
                config.text = "앱 버전"
                config.secondaryText = viewModel.appVersion
                config.image = UIImage(systemName: "info.circle.fill")
                config.imageProperties.tintColor = Theme.Colors.secondaryLabel
                cell.selectionStyle = .none
            }
        }

        cell.contentConfiguration = config
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let sec = Section(rawValue: indexPath.section) else { return }

        switch sec {
        case .voice:
            guard let row = VoiceRow(rawValue: indexPath.row) else { return }
            if row == .speed {
                showVoiceSpeedPicker()
            }

        case .map:
            guard let row = MapRow(rawValue: indexPath.row) else { return }
            if row == .type {
                showMapTypePicker()
            }

        case .data:
            guard let row = DataRow(rawValue: indexPath.row) else { return }
            if row == .clearHistory && viewModel.searchHistoryCount.value > 0 {
                confirmClearSearchHistory()
            }

        case .info:
            break
        }
    }
}
