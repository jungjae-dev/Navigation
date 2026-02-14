import UIKit
import Combine
import MapKit

final class SearchViewController: UIViewController {

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case recentSearches = 0
        case completions = 1
    }

    // MARK: - UI Components

    private let searchBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.secondaryBackground
        view.layer.cornerRadius = Theme.CornerRadius.medium
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = Theme.Colors.label
        return button
    }()

    private let searchTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "장소 또는 주소 검색"
        textField.font = Theme.Fonts.body
        textField.borderStyle = .none
        textField.returnKeyType = .search
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        return textField
    }()

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = Theme.Colors.background
        tableView.keyboardDismissMode = .onDrag
        return tableView
    }()

    // MARK: - Properties

    private let viewModel: SearchViewModel
    private var cancellables = Set<AnyCancellable>()
    private var isSearching = false

    var onSearchResults: (([MKMapItem]) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Init

    init(viewModel: SearchViewModel) {
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
        setupActions()
        bindViewModel()
        viewModel.loadRecentSearches()
        searchTextField.becomeFirstResponder()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        view.addSubview(searchBar)
        searchBar.addSubview(backButton)
        searchBar.addSubview(searchTextField)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            searchBar.heightAnchor.constraint(equalToConstant: 48),

            backButton.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: Theme.Spacing.sm),
            backButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            searchTextField.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: Theme.Spacing.sm),
            searchTextField.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -Theme.Spacing.md),
            searchTextField.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Theme.Spacing.md),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CompletionCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "RecentCell")
    }

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        searchTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        searchTextField.delegate = self
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.completions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        viewModel.recentSearches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        viewModel.errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showError(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private var showRecentSection: Bool {
        !isSearching && !viewModel.recentSearches.value.isEmpty
    }

    // MARK: - Actions

    @objc private func backTapped() {
        viewModel.clearSearch()
        onDismiss?()
        dismiss(animated: true)
    }

    @objc private func textFieldDidChange() {
        guard let text = searchTextField.text else { return }
        isSearching = !text.isEmpty
        viewModel.updateQuery(text)

        if text.isEmpty {
            viewModel.loadRecentSearches()
        }
    }

    @objc private func clearAllHistoryTapped() {
        viewModel.clearAllRecentSearches()
    }

    private func handleSearchResults(_ results: [MKMapItem]) {
        guard !results.isEmpty else { return }
        onSearchResults?(results)
        dismiss(animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "오류", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SearchViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .recentSearches:
            return showRecentSection ? viewModel.recentSearches.value.count : 0
        case .completions:
            return isSearching ? viewModel.completions.value.count : 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sec = Section(rawValue: indexPath.section) else { return UITableViewCell() }

        switch sec {
        case .recentSearches:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RecentCell", for: indexPath)
            let history = viewModel.recentSearches.value[indexPath.row]

            var config = cell.defaultContentConfiguration()
            config.text = history.placeName
            config.secondaryText = history.address
            config.image = UIImage(systemName: "clock.arrow.circlepath")
            config.imageProperties.tintColor = Theme.Colors.secondaryLabel
            cell.contentConfiguration = config
            return cell

        case .completions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "CompletionCell", for: indexPath)
            let completion = viewModel.completions.value[indexPath.row]

            var config = cell.defaultContentConfiguration()
            config.text = completion.title
            config.secondaryText = completion.subtitle
            config.image = UIImage(systemName: "magnifyingglass")
            config.imageProperties.tintColor = Theme.Colors.secondaryLabel
            cell.contentConfiguration = config
            return cell
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sec = Section(rawValue: section), sec == .recentSearches, showRecentSection else {
            return nil
        }

        let headerView = UIView()
        headerView.backgroundColor = Theme.Colors.background

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "최근 검색"
        titleLabel.font = Theme.Fonts.headline
        titleLabel.textColor = Theme.Colors.label

        let clearButton = UIButton(type: .system)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setTitle("전체 삭제", for: .normal)
        clearButton.titleLabel?.font = Theme.Fonts.footnote
        clearButton.tintColor = Theme.Colors.destructive
        clearButton.addTarget(self, action: #selector(clearAllHistoryTapped), for: .touchUpInside)

        headerView.addSubview(titleLabel)
        headerView.addSubview(clearButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: Theme.Spacing.lg),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -Theme.Spacing.lg),
            clearButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .recentSearches:
            return showRecentSection ? 44 : 0
        case .completions:
            return isSearching && !viewModel.completions.value.isEmpty ? 44 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .recentSearches:
            return nil // Custom header view
        case .completions:
            return isSearching && !viewModel.completions.value.isEmpty ? "검색 결과" : nil
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let sec = Section(rawValue: indexPath.section) else { return false }
        return sec == .recentSearches
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              let sec = Section(rawValue: indexPath.section),
              sec == .recentSearches else { return }

        let history = viewModel.recentSearches.value[indexPath.row]
        viewModel.deleteRecentSearch(history)
    }
}

// MARK: - UITableViewDelegate

extension SearchViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let sec = Section(rawValue: indexPath.section) else { return }

        switch sec {
        case .recentSearches:
            let history = viewModel.recentSearches.value[indexPath.row]
            let results = viewModel.selectRecentSearch(history)
            handleSearchResults(results)

        case .completions:
            let completion = viewModel.completions.value[indexPath.row]
            Task {
                if let results = await viewModel.selectCompletion(completion) {
                    handleSearchResults(results)
                }
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension SearchViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let query = textField.text, !query.isEmpty else { return false }

        Task {
            if let results = await viewModel.executeSearch(query: query) {
                handleSearchResults(results)
            }
        }

        textField.resignFirstResponder()
        return true
    }
}
