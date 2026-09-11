import UIKit

/// 주차 관측 로그(.ndjson) 파일 목록 — RecordingFileListViewController 패턴 준용 (DR-003, T042).
/// 스와이프: 삭제(확인 얼럿) / 공유. 탭: 공유.
final class ParkingLogListViewController: UIViewController {

    // MARK: - UI

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        return tableView
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "기록된 주차 관측 로그가 없습니다\n(내 차 찾기 디버그를 켜면 기록됩니다)"
        label.numberOfLines = 0
        label.font = Theme.Fonts.body
        label.textColor = Theme.Colors.secondaryLabel
        label.textAlignment = .center
        return label
    }()

    // MARK: - Properties

    private var files: [URL] = []

    var onDismiss: (() -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        loadFiles()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // MARK: - Setup

    private func setupUI() {
        title = "주차 관측 로그"
        view.backgroundColor = Theme.Colors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            primaryAction: UIAction { [weak self] _ in self?.onDismiss?() }
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.shareAll() }
        )

        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ParkingLogCell")

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.xl),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.xl),
        ])
    }

    // MARK: - Data

    static func logDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ParkingLogs", isDirectory: true)
    }

    static func logFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: logDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "ndjson" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private func loadFiles() {
        files = Self.logFiles()
        tableView.reloadData()
        emptyLabel.isHidden = !files.isEmpty
        tableView.isHidden = files.isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !files.isEmpty
    }

    // MARK: - Actions

    private func confirmDelete(at indexPath: IndexPath) {
        let file = files[indexPath.row]
        let alert = UIAlertController(
            title: "삭제",
            message: "\(file.lastPathComponent)을(를) 삭제하시겠습니까?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            try? FileManager.default.removeItem(at: file)
            self?.loadFiles()
        })
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    private func shareFile(at indexPath: IndexPath) {
        let activityVC = UIActivityViewController(activityItems: [files[indexPath.row]], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    private func shareAll() {
        guard !files.isEmpty else { return }
        let activityVC = UIActivityViewController(activityItems: files, applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activityVC, animated: true)
    }

    // MARK: - Helpers

    private func subtitle(for file: URL) -> String {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        let date = values?.contentModificationDate.map { formatter.string(from: $0) } ?? "-"
        let size = values?.fileSize.map { bytes -> String in
            bytes < 1024 ? "\(bytes)B"
                : bytes < 1024 * 1024 ? String(format: "%.1fKB", Double(bytes) / 1024)
                : String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        } ?? "-"
        return "\(date) | \(size)"
    }
}

// MARK: - UITableViewDataSource

extension ParkingLogListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ParkingLogCell", for: indexPath)
        let file = files[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = file.lastPathComponent
        config.secondaryText = subtitle(for: file)
        config.image = UIImage(systemName: "parkingsign.circle")
        config.imageProperties.tintColor = .systemIndigo
        cell.contentConfiguration = config
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ParkingLogListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        shareFile(at: indexPath)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            self?.confirmDelete(at: indexPath)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash.fill")

        let shareAction = UIContextualAction(style: .normal, title: "공유") { [weak self] _, _, completion in
            self?.shareFile(at: indexPath)
            completion(true)
        }
        shareAction.backgroundColor = .systemBlue
        shareAction.image = UIImage(systemName: "square.and.arrow.up")

        return UISwipeActionsConfiguration(actions: [deleteAction, shareAction])
    }
}
