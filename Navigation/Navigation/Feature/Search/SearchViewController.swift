import UIKit
import Combine
import MapKit

final class SearchViewController: UIViewController {

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

        viewModel.errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showError(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        viewModel.clearSearch()
        onDismiss?()
        dismiss(animated: true)
    }

    @objc private func textFieldDidChange() {
        guard let text = searchTextField.text else { return }
        viewModel.updateQuery(text)
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.completions.value.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.completions.value.isEmpty ? nil : "검색 결과"
    }
}

// MARK: - UITableViewDelegate

extension SearchViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let completion = viewModel.completions.value[indexPath.row]

        Task {
            if let results = await viewModel.selectCompletion(completion) {
                handleSearchResults(results)
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
