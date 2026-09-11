import UIKit
import Combine

/// 즐겨찾기 전체 목록 화면. 카테고리 분류·정렬은 없음 — 저장된 항목을 모두 보고
/// 선택해 경로를 시작하거나, 편집 모드에서 일부·전체를 골라 삭제하는 것만 지원(v1.0 최소 범위).
final class FavoritesListViewController: UIViewController {

    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()
    private var favorites: [FavoritePlace] = []

    var onSelectFavorite: ((FavoritePlace) -> Void)?

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
        label.text = "저장된 즐겨찾기가 없습니다"
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
        title = "즐겨찾기"
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FavoriteRowCell")
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
        viewModel.favorites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] favorites in
                guard let self else { return }
                // 스와이프/편집 삭제는 여기 도착하기 전에 이미 로컬 배열·테이블을 동기로
                // 반영해둠 — 같은 내용이면 다시 reloadData()하지 않아야 방금 재생 중인
                // 삭제 애니메이션이 끊기지 않음. 다른 화면에서 즐겨찾기가 바뀐 경우에만 갱신.
                guard favorites.map(\.id) != self.favorites.map(\.id) else { return }
                self.favorites = favorites
                self.emptyLabel.isHidden = !favorites.isEmpty
                self.editButton.isEnabled = !favorites.isEmpty
                self.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    private func iconName(for category: String) -> String {
        switch category {
        case "home": return "house.fill"
        case "work": return "building.2.fill"
        case "cafe": return "cup.and.saucer.fill"
        case "gym": return "dumbbell.fill"
        case "school": return "graduationcap.fill"
        default: return "star.fill"
        }
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
        let allSelected = (tableView.indexPathsForSelectedRows?.count ?? 0) == favorites.count
        if allSelected {
            for row in 0..<favorites.count {
                tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
            }
        } else {
            for row in 0..<favorites.count {
                tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
            }
        }
        updateToolbar()
    }

    @objc private func deleteSelected() {
        let indexPaths = (tableView.indexPathsForSelectedRows ?? []).sorted { $0.row > $1.row }
        guard !indexPaths.isEmpty else { return }
        let toDelete = indexPaths.map { favorites[$0.row] }

        for indexPath in indexPaths {
            favorites.remove(at: indexPath.row)
        }
        tableView.deleteRows(at: indexPaths, with: .automatic)
        emptyLabel.isHidden = !favorites.isEmpty
        editButton.isEnabled = !favorites.isEmpty
        viewModel.deleteFavorites(toDelete)

        toggleEditing()
    }

    private func updateToolbar() {
        let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0
        selectAllButton.title = selectedCount == favorites.count && !favorites.isEmpty ? "전체 해제" : "전체 선택"
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

extension FavoritesListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        favorites.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FavoriteRowCell", for: indexPath)
        let favorite = favorites[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = favorite.name
        config.secondaryText = favorite.address
        config.image = UIImage(systemName: iconName(for: favorite.category))
        config.imageProperties.tintColor = .systemYellow
        cell.contentConfiguration = config
        cell.accessoryType = .none
        return cell
    }
}

// MARK: - UITableViewDelegate

extension FavoritesListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            updateToolbar()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectFavorite?(favorites[indexPath.row])
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
        let favorite = favorites[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            // viewModel.favorites는 .receive(on: .main)이라 같은 메인 스레드라도
            // 다음 런루프에 비동기로 도착함 — completion(true)가 트리거하는 UIKit의
            // 암묵적 행 삭제 애니메이션은 그 전에 실행되므로, 여기서 로컬 배열과
            // 테이블을 먼저 동기적으로 맞춰야 "Invalid number of rows" 크래시가 안 남.
            self.favorites.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.emptyLabel.isHidden = !self.favorites.isEmpty
            self.editButton.isEnabled = !self.favorites.isEmpty
            self.viewModel.deleteFavorite(favorite)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
