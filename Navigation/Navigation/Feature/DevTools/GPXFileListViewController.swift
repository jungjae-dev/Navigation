import UIKit
import Combine

final class GPXFileListViewController: UIViewController {

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
        label.text = "녹화된 GPX 파일이 없습니다"
        label.font = Theme.Fonts.body
        label.textColor = Theme.Colors.secondaryLabel
        label.textAlignment = .center
        return label
    }()

    // MARK: - Properties

    private var records: [GPXRecord] = []
    private let dataService: DataService

    var onDismiss: (() -> Void)?
    var onSelectFile: ((GPXRecord) -> Void)?

    // MARK: - Init

    init(dataService: DataService = .shared) {
        self.dataService = dataService
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
        loadRecords()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadRecords()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.title = "GPX 파일"

        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
        backButton.tintColor = Theme.Colors.label
        navigationItem.leftBarButtonItem = backButton

        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "GPXFileCell")
    }

    // MARK: - Data

    private func loadRecords() {
        records = dataService.fetchGPXRecords()
        tableView.reloadData()
        emptyLabel.isHidden = !records.isEmpty
        tableView.isHidden = records.isEmpty
    }

    // MARK: - Actions

    @objc private func backTapped() {
        onDismiss?()
    }

    private func confirmDelete(at indexPath: IndexPath) {
        let record = records[indexPath.row]

        let alert = UIAlertController(
            title: "삭제",
            message: "\(record.fileName)을(를) 삭제하시겠습니까?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            self?.dataService.deleteGPXRecord(record)
            self?.loadRecords()
        })

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }

    private func shareFile(at indexPath: IndexPath) {
        let record = records[indexPath.row]
        let activityVC = UIActivityViewController(
            activityItems: [record.fileURL],
            applicationActivities: nil
        )
        present(activityVC, animated: true)
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

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        }
        if bytes < 1024 * 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024)
        }
        return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - UITableViewDataSource

extension GPXFileListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GPXFileCell", for: indexPath)
        let record = records[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = record.fileName
        config.secondaryText = "\(formattedDate(record.recordedAt)) | \(formattedDistance(record.distance)) | \(formattedDuration(record.duration)) | \(record.pointCount)pts"
        config.image = UIImage(systemName: "doc.text.fill")
        config.imageProperties.tintColor = .systemOrange
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator

        return cell
    }
}

// MARK: - UITableViewDelegate

extension GPXFileListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = records[indexPath.row]
        onSelectFile?(record)
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
