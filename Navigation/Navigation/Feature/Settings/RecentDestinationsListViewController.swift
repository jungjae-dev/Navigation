import UIKit
import Combine

/// 최근 목적지 전체 목록 화면. FavoritesListViewController와 동일한 구조 —
/// 선택해 경로를 시작하거나, 편집 모드에서 일부·전체를 골라 삭제.
final class RecentDestinationsListViewController: UIViewController {

    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()
    private var histories: [SearchHistory] = []

    var onSelectHistory: ((SearchHistory) -> Void)?

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        tableView.allowsMultipleSelectionDuringEditing = true
        return tableView
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "최근 목적지가 없습니다"
        label.textColor = Theme.Colors.secondaryLabel
        label.font = Theme.Fonts.body
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var editButton = UIBarButtonItem(
        title: "편집", style: .plain, target: self, action: #selector(toggleEditing)
    )
    private lazy var selectAllButton = UIBarButtonItem(
        title: "전체 선택", style: .plain, target: self, action: #selector(toggleSelectAll)
    )
    private lazy var deleteButton = UIBarButtonItem(
        title: "삭제", style: .plain, target: self, action: #selector(deleteSelected)
    )

    // MARK: - Init

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "최근 목적지"
        view.backgroundColor = Theme.Colors.background
        navigationItem.rightBarButtonItem = editButton

        setupTableView()
        bindViewModel()
        updateToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.setToolbarHidden(!isEditing, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HistoryRowCell")
        tableView.rowHeight = 60

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

    private func bindViewModel() {
        viewModel.recentSearches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] histories in
                guard let self else { return }
                // 스와이프/편집 삭제는 여기 도착하기 전에 이미 로컬 배열·테이블을 동기로
                // 반영해둠 — 같은 내용이면 다시 reloadData()하지 않아야 방금 재생 중인
                // 삭제 애니메이션이 끊기지 않음. 다른 화면에서 기록이 바뀐 경우에만 갱신.
                guard histories.map(\.id) != self.histories.map(\.id) else { return }
                self.histories = histories
                self.emptyLabel.isHidden = !histories.isEmpty
                self.editButton.isEnabled = !histories.isEmpty
                self.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    // MARK: - Editing

    @objc private func toggleEditing() {
        let editing = !isEditing
        setEditing(editing, animated: true)
        tableView.setEditing(editing, animated: true)
        editButton.title = editing ? "완료" : "편집"
        navigationController?.setToolbarHidden(!editing, animated: true)
        updateToolbar()
    }

    @objc private func toggleSelectAll() {
        let allSelected = (tableView.indexPathsForSelectedRows?.count ?? 0) == histories.count
        if allSelected {
            for row in 0..<histories.count {
                tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
            }
        } else {
            for row in 0..<histories.count {
                tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
            }
        }
        updateToolbar()
    }

    @objc private func deleteSelected() {
        let indexPaths = (tableView.indexPathsForSelectedRows ?? []).sorted { $0.row > $1.row }
        guard !indexPaths.isEmpty else { return }
        let toDelete = indexPaths.map { histories[$0.row] }

        for indexPath in indexPaths {
            histories.remove(at: indexPath.row)
        }
        tableView.deleteRows(at: indexPaths, with: .automatic)
        emptyLabel.isHidden = !histories.isEmpty
        editButton.isEnabled = !histories.isEmpty
        viewModel.deleteSearchHistories(toDelete)

        toggleEditing()
    }

    private func updateToolbar() {
        let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0
        selectAllButton.title = selectedCount == histories.count && !histories.isEmpty ? "전체 해제" : "전체 선택"
        deleteButton.title = selectedCount > 0 ? "삭제(\(selectedCount))" : "삭제"
        deleteButton.isEnabled = selectedCount > 0
        toolbarItems = [
            selectAllButton,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            deleteButton,
        ]
    }
}

// MARK: - UITableViewDataSource

extension RecentDestinationsListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        histories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryRowCell", for: indexPath)
        let history = histories[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = history.placeName
        config.secondaryText = history.address
        config.image = UIImage(systemName: "clock.arrow.circlepath")
        config.imageProperties.tintColor = Theme.Colors.secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .none
        return cell
    }
}

// MARK: - UITableViewDelegate

extension RecentDestinationsListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            updateToolbar()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectHistory?(histories[indexPath.row])
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditing {
            updateToolbar()
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let history = histories[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            self.histories.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.emptyLabel.isHidden = !self.histories.isEmpty
            self.editButton.isEnabled = !self.histories.isEmpty
            self.viewModel.deleteSearchHistory(history)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
