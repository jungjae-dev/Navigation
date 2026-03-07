import UIKit

final class SearchResultDrawerViewController: UIViewController {

    // MARK: - UI Components

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        tableView.separatorStyle = .singleLine
        tableView.alwaysBounceVertical = false
        return tableView
    }()

    // MARK: - Properties

    private var searchResults: [Place] = []
    private var highlightedIndex: Int = 0

    var onItemSelected: ((Place, Int) -> Void)?
    var onFocusedIndexChanged: ((Int) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        headerView.setTitle("검색 결과", alignment: .center)
        headerView.addRightAction(closeButton)

        view.addSubview(headerView)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(
                equalTo: headerView.bottomAnchor,
                constant: Theme.Drawer.Layout.contentTopPadding
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
    }

    // MARK: - Public Methods

    func updateResults(_ results: [Place]) {
        searchResults = results
        highlightedIndex = 0
        tableView.reloadData()
    }

    func place(at index: Int) -> Place? {
        guard index < searchResults.count else { return nil }
        return searchResults[index]
    }

    func scrollToIndex(_ index: Int, animated: Bool = true) {
        guard index < searchResults.count else { return }
        let oldIndex = highlightedIndex
        highlightedIndex = index

        let indexPathsToReload = [IndexPath(row: oldIndex, section: 0),
                                  IndexPath(row: index, section: 0)]
            .filter { $0.row < searchResults.count }
        tableView.reloadRows(at: indexPathsToReload, with: .none)

        tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: animated)
    }
}

// MARK: - UITableViewDataSource

extension SearchResultDrawerViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "SearchResultCell",
            for: indexPath
        ) as? SearchResultCell else {
            return UITableViewCell()
        }

        let item = searchResults[indexPath.row]
        let isHighlighted = indexPath.row == highlightedIndex
        cell.configure(with: item, isHighlighted: isHighlighted)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SearchResultDrawerViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = searchResults[indexPath.row]
        onItemSelected?(item, indexPath.row)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyTopIndex()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { notifyTopIndex() }
    }

    // MARK: - Private Helpers

    private func notifyTopIndex() {
        guard let topIndexPath = tableView.indexPathsForVisibleRows?.first else { return }
        onFocusedIndexChanged?(topIndexPath.row)
    }
}
