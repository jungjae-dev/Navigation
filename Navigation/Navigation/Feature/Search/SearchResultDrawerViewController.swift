import UIKit
import MapKit

final class SearchResultDrawerViewController: UIViewController {

    // MARK: - Constants

    static let titleBarHeight: CGFloat = 44

    // MARK: - UI Components

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.label
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "xmark.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        return button
    }()

    private let titleSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.separator
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

        view.addSubview(titleLabel)
        view.addSubview(closeButton)
        view.addSubview(titleSeparator)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.topAnchor, constant: Self.titleBarHeight / 2),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            titleSeparator.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.titleBarHeight),
            titleSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            tableView.topAnchor.constraint(equalTo: titleSeparator.bottomAnchor),
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

    func updateResults(_ results: [MKMapItem]) {
        searchResults = results
        highlightedIndex = 0
        tableView.reloadData()
    }

    func mapItem(at index: Int) -> MKMapItem? {
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
