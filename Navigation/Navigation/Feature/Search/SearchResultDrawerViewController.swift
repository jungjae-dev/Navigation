import UIKit
import MapKit

final class SearchResultDrawerViewController: UIViewController {

    // MARK: - UI Components

    private let handleBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.separator
        view.layer.cornerRadius = 2
        return view
    }()

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        tableView.separatorStyle = .singleLine
        tableView.alwaysBounceVertical = false
        return tableView
    }()

    // MARK: - Properties

    private var searchResults: [MKMapItem] = []
    private var highlightedIndex: Int = 0

    var onItemSelected: ((MKMapItem, Int) -> Void)?
    var onFocusedIndexChanged: ((Int) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        view.addSubview(handleBar)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            handleBar.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Spacing.sm),
            handleBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handleBar.widthAnchor.constraint(equalToConstant: 36),
            handleBar.heightAnchor.constraint(equalToConstant: 4),

            tableView.topAnchor.constraint(equalTo: handleBar.bottomAnchor, constant: Theme.Spacing.sm),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
    }

    // MARK: - Public Methods

    func updateResults(_ results: [MKMapItem]) {
        searchResults = results
        highlightedIndex = 0
        tableView.reloadData()
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

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        DrawerScrollHelper.handleScrollEdgeTransition(
            scrollView: scrollView,
            velocity: velocity,
            sheet: sheetPresentationController
        )
    }

    // MARK: - Private Helpers

    private func notifyTopIndex() {
        guard let topIndexPath = tableView.indexPathsForVisibleRows?.first else { return }
        onFocusedIndexChanged?(topIndexPath.row)
    }
}
