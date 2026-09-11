import UIKit
import Combine

/// 즐겨찾기 전체 목록 화면. 카테고리 분류·정렬은 없음 — 저장된 항목을 모두 보고
/// 삭제하거나 선택해 경로를 시작하는 것만 지원(v1.0 최소 범위).
final class FavoritesListViewController: UIViewController {

    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()
    private var favorites: [FavoritePlace] = []

    var onSelectFavorite: ((FavoritePlace) -> Void)?

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
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

        setupTableView()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
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
                self.favorites = favorites
                self.emptyLabel.isHidden = !favorites.isEmpty
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
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectFavorite?(favorites[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let favorite = favorites[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            self?.viewModel.deleteFavorite(favorite)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
