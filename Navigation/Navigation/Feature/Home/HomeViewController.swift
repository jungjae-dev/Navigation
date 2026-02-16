import UIKit
import Combine

final class HomeViewController: UIViewController {

    // MARK: - Collection Sections

    private enum HomeSection: Int, CaseIterable {
        case favorites = 0
        case recentSearches = 1
    }

    // MARK: - UI Components

    private let searchBarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.secondaryBackground
        view.layer.cornerRadius = Theme.CornerRadius.medium
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = Theme.Shadow.offset
        view.layer.shadowRadius = Theme.Shadow.radius
        return view
    }()

    private let searchIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "magnifyingglass")
        imageView.tintColor = Theme.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let searchLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "여기서 검색"
        label.font = Theme.Fonts.body
        label.textColor = Theme.Colors.secondaryLabel
        return label
    }()

    private let settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "gearshape.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.secondaryLabel
        button.backgroundColor = Theme.Colors.secondaryBackground
        button.layer.cornerRadius = 20
        button.layer.shadowColor = Theme.Shadow.color
        button.layer.shadowOpacity = Theme.Shadow.opacity
        button.layer.shadowOffset = Theme.Shadow.offset
        button.layer.shadowRadius = Theme.Shadow.radius
        return button
    }()

    private lazy var bottomPanel: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.background.withAlphaComponent(0.95)
        view.layer.cornerRadius = Theme.CornerRadius.large
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = Theme.Shadow.radius
        return view
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = createCompositionalLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(FavoriteCell.self, forCellWithReuseIdentifier: FavoriteCell.reuseIdentifier)
        cv.register(RecentSearchCell.self, forCellWithReuseIdentifier: RecentSearchCell.reuseIdentifier)
        cv.register(HomeSectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: HomeSectionHeaderView.reuseIdentifier)
        return cv
    }()

    // MARK: - Properties

    private let viewModel: HomeViewModel
    private let mapViewController: MapViewController
    private var cancellables = Set<AnyCancellable>()
    private var bottomPanelHeightConstraint: NSLayoutConstraint!

    var onSearchBarTapped: (() -> Void)?
    var onFavoriteTapped: ((FavoritePlace) -> Void)?
    var onRecentSearchTapped: ((SearchHistory) -> Void)?
    var onSettingsTapped: (() -> Void)?

    // MARK: - Init

    init(viewModel: HomeViewModel, mapViewController: MapViewController) {
        self.viewModel = viewModel
        self.mapViewController = mapViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapChild()
        setupSearchBar()
        setupSettingsButton()
        setupBottomPanel()
        setupAccessibility()
        bindViewModel()
        handleInitialPermission()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadHomeData()
    }

    // MARK: - Setup

    private func setupMapChild() {
        addChild(mapViewController)
        view.addSubview(mapViewController.view)
        mapViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mapViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mapViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        mapViewController.didMove(toParent: self)
    }

    private func setupSearchBar() {
        view.addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIcon)
        searchBarContainer.addSubview(searchLabel)

        NSLayoutConstraint.activate([
            searchBarContainer.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm
            ),
            searchBarContainer.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.lg
            ),
            searchBarContainer.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg
            ),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 48),

            searchIcon.leadingAnchor.constraint(
                equalTo: searchBarContainer.leadingAnchor, constant: Theme.Spacing.md
            ),
            searchIcon.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20),

            searchLabel.leadingAnchor.constraint(
                equalTo: searchIcon.trailingAnchor, constant: Theme.Spacing.sm
            ),
            searchLabel.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchLabel.trailingAnchor.constraint(
                equalTo: searchBarContainer.trailingAnchor, constant: -Theme.Spacing.md
            ),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(searchBarTapped))
        searchBarContainer.addGestureRecognizer(tapGesture)
        searchBarContainer.isUserInteractionEnabled = true
    }

    private func setupSettingsButton() {
        view.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: Theme.Spacing.sm),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            settingsButton.widthAnchor.constraint(equalToConstant: 40),
            settingsButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
    }

    private func setupBottomPanel() {
        view.addSubview(bottomPanel)
        bottomPanel.addSubview(collectionView)

        bottomPanelHeightConstraint = bottomPanel.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            bottomPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomPanelHeightConstraint,

            collectionView.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: Theme.Spacing.lg),
            collectionView.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomPanel.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: - Compositional Layout

    private func createCompositionalLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let section = HomeSection(rawValue: sectionIndex) else { return nil }
            switch section {
            case .favorites:
                return self?.createFavoritesSection()
            case .recentSearches:
                return self?.createRecentSearchesSection()
            }
        }
    }

    private func createFavoritesSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(72), heightDimension: .absolute(72))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(72), heightDimension: .absolute(72))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = Theme.Spacing.sm
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: Theme.Spacing.lg, bottom: Theme.Spacing.md, trailing: Theme.Spacing.lg)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(36))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = [header]

        return section
    }

    private func createRecentSearchesSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(52))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(52))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: Theme.Spacing.md, trailing: 0)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(36))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = [header]

        return section
    }

    // MARK: - Accessibility

    private func setupAccessibility() {
        searchBarContainer.isAccessibilityElement = true
        searchBarContainer.accessibilityLabel = "검색"
        searchBarContainer.accessibilityHint = "탭하여 장소를 검색합니다"
        searchBarContainer.accessibilityTraits = .searchField

        settingsButton.accessibilityLabel = "설정"
        settingsButton.accessibilityHint = "앱 설정을 엽니다"
    }

    // MARK: - Binding

    private func bindViewModel() {
        viewModel.authStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleAuthStatusChange(status)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(viewModel.favorites, viewModel.recentSearches)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] favorites, searches in
                self?.updateBottomPanel(hasFavorites: !favorites.isEmpty, hasSearches: !searches.isEmpty)
                self?.collectionView.reloadData()
            }
            .store(in: &cancellables)
    }

    // MARK: - Bottom Panel

    private func updateBottomPanel(hasFavorites: Bool, hasSearches: Bool) {
        let hasContent = hasFavorites || hasSearches

        let favHeight: CGFloat = hasFavorites ? (36 + 72 + Theme.Spacing.md) : 0
        let searchCount = min(viewModel.recentSearches.value.count, 5)
        let searchHeight: CGFloat = hasSearches ? (36 + CGFloat(searchCount) * 52 + Theme.Spacing.md) : 0
        let safeArea: CGFloat = view.safeAreaInsets.bottom
        let totalHeight = hasContent ? (Theme.Spacing.lg + favHeight + searchHeight + safeArea) : 0

        UIView.animate(withDuration: 0.3) {
            self.bottomPanelHeightConstraint.constant = totalHeight
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func searchBarTapped() {
        onSearchBarTapped?()
    }

    @objc private func settingsTapped() {
        onSettingsTapped?()
    }

    // MARK: - Permission Handling

    private func handleInitialPermission() {
        let status = viewModel.authStatus.value
        if status == .notDetermined {
            viewModel.requestLocationPermission()
        } else if status.isAuthorized {
            viewModel.startLocationUpdates()
        }
    }

    private func handleAuthStatusChange(_ status: LocationAuthStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            viewModel.startLocationUpdates()

        case .denied, .restricted:
            showLocationDeniedAlert()

        case .notDetermined:
            break
        }
    }

    private func showLocationDeniedAlert() {
        let alert = UIAlertController(
            title: "위치 권한 필요",
            message: "지도에 현재 위치를 표시하려면 위치 권한이 필요합니다. 설정에서 위치 권한을 허용해주세요.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "설정으로 이동", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))

        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDataSource

extension HomeViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        HomeSection.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sec = HomeSection(rawValue: section) else { return 0 }
        switch sec {
        case .favorites:
            return viewModel.favorites.value.count
        case .recentSearches:
            return min(viewModel.recentSearches.value.count, 5)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let sec = HomeSection(rawValue: indexPath.section) else {
            return UICollectionViewCell()
        }

        switch sec {
        case .favorites:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FavoriteCell.reuseIdentifier, for: indexPath
            ) as? FavoriteCell else { return UICollectionViewCell() }

            let favorite = viewModel.favorites.value[indexPath.item]
            cell.configure(with: favorite)
            return cell

        case .recentSearches:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RecentSearchCell.reuseIdentifier, for: indexPath
            ) as? RecentSearchCell else { return UICollectionViewCell() }

            let history = viewModel.recentSearches.value[indexPath.item]
            cell.configure(with: history)
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: HomeSectionHeaderView.reuseIdentifier, for: indexPath
              ) as? HomeSectionHeaderView,
              let sec = HomeSection(rawValue: indexPath.section) else {
            return UICollectionReusableView()
        }

        switch sec {
        case .favorites:
            header.configure(title: "즐겨찾기", showIcon: true, iconName: "star.fill")
        case .recentSearches:
            header.configure(title: "최근 검색", showIcon: true, iconName: "clock.arrow.circlepath")
        }

        return header
    }
}

// MARK: - UICollectionViewDelegate

extension HomeViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let sec = HomeSection(rawValue: indexPath.section) else { return }

        switch sec {
        case .favorites:
            let favorite = viewModel.favorites.value[indexPath.item]
            onFavoriteTapped?(favorite)

        case .recentSearches:
            let history = viewModel.recentSearches.value[indexPath.item]
            onRecentSearchTapped?(history)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let sec = HomeSection(rawValue: indexPath.section) else { return nil }

        switch sec {
        case .favorites:
            let favorite = viewModel.favorites.value[indexPath.item]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let editAction = UIAction(
                    title: "편집",
                    image: UIImage(systemName: "pencil")
                ) { _ in
                    self?.showFavoriteEditAlert(for: favorite)
                }

                let deleteAction = UIAction(
                    title: "삭제",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.viewModel.deleteFavorite(favorite)
                }

                return UIMenu(title: favorite.name, children: [editAction, deleteAction])
            }

        case .recentSearches:
            let history = viewModel.recentSearches.value[indexPath.item]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let navigateAction = UIAction(
                    title: "재안내",
                    image: UIImage(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                ) { _ in
                    self?.onRecentSearchTapped?(history)
                }

                let deleteAction = UIAction(
                    title: "삭제",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.viewModel.deleteSearchHistory(history)
                }

                return UIMenu(title: history.placeName, children: [navigateAction, deleteAction])
            }
        }
    }

    private func showFavoriteEditAlert(for favorite: FavoritePlace) {
        let alert = UIAlertController(title: "즐겨찾기 편집", message: nil, preferredStyle: .alert)

        alert.addTextField { textField in
            textField.text = favorite.name
            textField.placeholder = "이름"
        }

        alert.addAction(UIAlertAction(title: "저장", style: .default) { [weak self] _ in
            let newName = alert.textFields?.first?.text ?? favorite.name
            self?.viewModel.editFavorite(favorite, name: newName, category: favorite.category)
        })

        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - Section Header View

final class HomeSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "HomeSectionHeader"

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Theme.Colors.primary
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.label
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(iconImageView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.lg),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Theme.Spacing.xs),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, showIcon: Bool, iconName: String) {
        titleLabel.text = title
        iconImageView.isHidden = !showIcon
        iconImageView.image = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
    }
}
