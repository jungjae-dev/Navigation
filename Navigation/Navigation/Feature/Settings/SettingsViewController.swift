import UIKit
import Combine
import PhotosUI

final class SettingsViewController: UIViewController {

    // MARK: - Section & Row

    private enum Section: Int, CaseIterable {
        case voice = 0
        case transport = 1
        case map = 2
        case vehicle = 3
        case haptic = 4
        case data = 5
        case info = 6
    }

    private enum VoiceRow: Int, CaseIterable {
        case enabled = 0
        case speed = 1
    }

    private enum TransportRow: Int, CaseIterable {
        case defaultMode = 0
    }

    private enum MapRow: Int, CaseIterable {
        case type = 0
    }

    private enum VehicleRow: Int, CaseIterable {
        case preset = 0
        case customPhoto = 1
        case vehicle3D = 2
    }

    private enum HapticRow: Int, CaseIterable {
        case enabled = 0
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
    private var photoPickerHelper: PhotoPickerHelper?

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

        Publishers.CombineLatest3(
            viewModel.defaultTransportMode,
            viewModel.hapticEnabled,
            viewModel.vehiclePreset
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.tableView.reloadData()
        }
        .store(in: &cancellables)

        VehicleIconService.shared.iconSourcePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
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

    @objc private func hapticSwitchChanged(_ sender: UISwitch) {
        viewModel.setHapticEnabled(sender.isOn)
    }

    @objc private func vehicle3DSwitchChanged(_ sender: UISwitch) {
        viewModel.setVehicle3DEnabled(sender.isOn)
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

    private func showTransportModePicker() {
        let alert = UIAlertController(title: "기본 이동수단", message: nil, preferredStyle: .actionSheet)

        for mode in [TransportMode.automobile, TransportMode.walking] {
            let action = UIAlertAction(title: mode.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setDefaultTransportMode(mode)
            }
            if mode == viewModel.defaultTransportMode.value {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    private func showVehiclePresetPicker() {
        let alert = UIAlertController(title: "차량 아이콘", message: nil, preferredStyle: .actionSheet)

        for preset in VehiclePreset.allCases {
            let action = UIAlertAction(title: preset.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setVehiclePreset(preset)
            }
            if preset == viewModel.vehiclePreset.value {
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

    private func showCustomPhotoOptions() {
        let hasCustom = VehicleIconService.shared.iconSourcePublisher.value.isCustom

        let alert = UIAlertController(title: "차량 아이콘 만들기", message: "사진에서 배경을 제거하여 차량 아이콘을 만듭니다.", preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "사진 선택", style: .default) { [weak self] _ in
            self?.pickPhotoForLiftSubject()
        })

        if hasCustom {
            alert.addAction(UIAlertAction(title: "커스텀 아이콘 제거", style: .destructive) { _ in
                VehicleIconService.shared.clearCustomImage()
            })
        }

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    private func pickPhotoForLiftSubject() {
        let helper = PhotoPickerHelper()
        self.photoPickerHelper = helper

        helper.pickImage(from: self) { [weak self] image in
            guard let self, let image else {
                self?.photoPickerHelper = nil
                return
            }
            self.processLiftSubject(image: image)
        }
    }

    private func processLiftSubject(image: UIImage) {
        guard #available(iOS 17.0, *) else {
            let alert = UIAlertController(
                title: "지원 불가",
                message: "배경 제거 기능은 iOS 17 이상에서 사용 가능합니다.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            present(alert, animated: true)
            return
        }

        let loadingAlert = UIAlertController(title: "처리 중", message: "배경을 제거하고 있습니다...", preferredStyle: .alert)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        loadingAlert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -16),
        ])
        present(loadingAlert, animated: true)

        Task {
            do {
                let service = LiftSubjectService()
                let cutout = try await service.liftSubject(from: image)
                let resized = cutout.resizedForVehicleIcon(maxSize: 100)

                loadingAlert.dismiss(animated: true) { [weak self] in
                    self?.showLiftSubjectPreview(cutout: resized)
                }
            } catch {
                loadingAlert.dismiss(animated: true) { [weak self] in
                    let errorAlert = UIAlertController(
                        title: "오류",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "확인", style: .default))
                    self?.present(errorAlert, animated: true)
                }
            }
            photoPickerHelper = nil
        }
    }

    private func showLiftSubjectPreview(cutout: UIImage) {
        let alert = UIAlertController(title: "아이콘 미리보기", message: "이 이미지를 차량 아이콘으로 사용하시겠습니까?\n\n\n\n\n", preferredStyle: .alert)

        let imageView = UIImageView(image: cutout)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.borderColor = UIColor.systemGray4.cgColor
        imageView.layer.borderWidth = 1
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        alert.view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 80),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
        ])

        alert.addAction(UIAlertAction(title: "사용", style: .default) { _ in
            let success = VehicleIconService.shared.setCustomImage(cutout)
            if !success {
                print("[Settings] Failed to save custom vehicle icon")
            }
        })

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UIImage Lift Subject Extension

private extension UIImage {
    func resizedForVehicleIcon(maxSize: CGFloat) -> UIImage {
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
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
        case .transport: return TransportRow.allCases.count
        case .map: return MapRow.allCases.count
        case .vehicle: return VehicleRow.allCases.count
        case .haptic: return HapticRow.allCases.count
        case .data: return DataRow.allCases.count
        case .info: return InfoRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .voice: return "음성 안내"
        case .transport: return "이동수단"
        case .map: return "지도"
        case .vehicle: return "차량 아이콘"
        case .haptic: return "햅틱"
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

        case .transport:
            guard let row = TransportRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .defaultMode:
                config.text = "기본 이동수단"
                config.secondaryText = viewModel.defaultTransportMode.value.displayName
                config.image = UIImage(systemName: viewModel.defaultTransportMode.value.iconName)
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

        case .vehicle:
            guard let row = VehicleRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .preset:
                config.text = "차량 아이콘 프리셋"
                config.secondaryText = viewModel.vehiclePreset.value.displayName
                config.image = UIImage(systemName: viewModel.vehiclePreset.value.iconName)
                config.imageProperties.tintColor = .systemOrange
                cell.accessoryType = .disclosureIndicator

            case .customPhoto:
                let hasCustom = VehicleIconService.shared.iconSourcePublisher.value.isCustom
                config.text = "사진에서 아이콘 만들기"
                config.secondaryText = hasCustom ? "사용 중" : nil
                config.image = UIImage(systemName: "photo.badge.plus")
                config.imageProperties.tintColor = .systemPurple
                cell.accessoryType = .disclosureIndicator

            case .vehicle3D:
                config.text = "3D 차량 모델"
                config.image = UIImage(systemName: "cube.fill")
                config.imageProperties.tintColor = .systemIndigo

                let toggle = UISwitch()
                toggle.isOn = viewModel.vehicle3DEnabled.value
                toggle.onTintColor = Theme.Colors.primary
                toggle.addTarget(self, action: #selector(vehicle3DSwitchChanged), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            }

        case .haptic:
            guard let row = HapticRow(rawValue: indexPath.row) else { return cell }
            switch row {
            case .enabled:
                config.text = "진동 피드백"
                config.image = UIImage(systemName: "iphone.radiowaves.left.and.right")
                config.imageProperties.tintColor = .systemTeal

                let toggle = UISwitch()
                toggle.isOn = viewModel.hapticEnabled.value
                toggle.onTintColor = Theme.Colors.primary
                toggle.addTarget(self, action: #selector(hapticSwitchChanged), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
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

        case .transport:
            guard let row = TransportRow(rawValue: indexPath.row) else { return }
            if row == .defaultMode {
                showTransportModePicker()
            }

        case .map:
            guard let row = MapRow(rawValue: indexPath.row) else { return }
            if row == .type {
                showMapTypePicker()
            }

        case .vehicle:
            guard let row = VehicleRow(rawValue: indexPath.row) else { return }
            switch row {
            case .preset:
                showVehiclePresetPicker()
            case .customPhoto:
                showCustomPhotoOptions()
            case .vehicle3D:
                break
            }

        case .haptic:
            break

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
