import UIKit
import Combine

final class HomeDrawerViewController: UIViewController {

    // MARK: - Collection Sections

    private enum HomeSection: Int, CaseIterable {
        case favorites = 0
        case recentSearches = 1
    }

    // MARK: - UI Components

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
        cv.alwaysBounceVertical = false
        return cv
    }()

    // MARK: - Properties

    private let viewModel: HomeViewModel
    private var cancellables = Set<AnyCancellable>()

    var onFavoriteTapped: ((FavoritePlace) -> Void)?
    var onRecentSearchTapped: ((SearchHistory) -> Void)?

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
        isModalInPresentation = true
        setupUI()
        bindViewModel()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Spacing.lg),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: - Binding

    private func bindViewModel() {
        Publishers.CombineLatest(viewModel.favorites, viewModel.recentSearches)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.collectionView.reloadData()
            }
            .store(in: &cancellables)
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

    // MARK: - Favorite Edit

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

// MARK: - UICollectionViewDataSource

extension HomeDrawerViewController: UICollectionViewDataSource {

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

extension HomeDrawerViewController: UICollectionViewDelegate {

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
