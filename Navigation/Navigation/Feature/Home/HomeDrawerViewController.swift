import UIKit
import Combine

final class HomeDrawerViewController: UIViewController {

    // MARK: - Detent

    enum DrawerDetent: CaseIterable {
        case small, medium, large

        func height(in containerView: UIView) -> CGFloat {
            let safeTop = containerView.safeAreaInsets.top
            let searchBarBottom = safeTop + Theme.Spacing.sm + 48 + Theme.Spacing.sm
            let maxHeight = containerView.bounds.height - searchBarBottom

            switch self {
            case .small:  return 200
            case .medium: return containerView.bounds.height * 0.5
            case .large:  return maxHeight
            }
        }
    }

    // MARK: - Collection Sections

    private enum HomeSection: Int, CaseIterable {
        case favorites = 0
        case recentSearches = 1
    }

    // MARK: - UI Components

    private let handleBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Theme.Colors.separator
        view.layer.cornerRadius = 2
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

    // MARK: - Drag State

    private var currentDetent: DrawerDetent = .small
    private var panStartHeight: CGFloat = 0
    var heightConstraint: NSLayoutConstraint!

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
        setupUI()
        setupPanGesture()
        bindViewModel()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background.withAlphaComponent(0.95)
        view.layer.cornerRadius = Theme.CornerRadius.large
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = Theme.Shadow.color
        view.layer.shadowOpacity = Theme.Shadow.opacity
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = Theme.Shadow.radius

        view.addSubview(handleBar)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            handleBar.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Spacing.sm),
            handleBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handleBar.widthAnchor.constraint(equalToConstant: 36),
            handleBar.heightAnchor.constraint(equalToConstant: 4),

            collectionView.topAnchor.constraint(equalTo: handleBar.bottomAnchor, constant: Theme.Spacing.sm),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
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

    // MARK: - Pan Gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let containerView = view.superview else { return }

        switch gesture.state {
        case .began:
            panStartHeight = heightConstraint.constant

        case .changed:
            let translation = gesture.translation(in: containerView)
            let minHeight = DrawerDetent.small.height(in: containerView)
            let maxHeight = DrawerDetent.large.height(in: containerView)
            let newHeight = panStartHeight - translation.y
            heightConstraint.constant = max(minHeight, min(maxHeight, newHeight))
            containerView.layoutIfNeeded()

        case .ended, .cancelled:
            let velocity = gesture.velocity(in: containerView)
            snapToNearestDetent(velocity: velocity.y, in: containerView)

        default:
            break
        }
    }

    private func snapToNearestDetent(velocity: CGFloat, in containerView: UIView) {
        let velocityThreshold: CGFloat = 500
        let currentHeight = heightConstraint.constant

        let targetDetent: DrawerDetent
        if abs(velocity) > velocityThreshold {
            // Fast swipe: move to next/previous detent based on direction
            let sortedDetents = DrawerDetent.allCases.sorted {
                $0.height(in: containerView) < $1.height(in: containerView)
            }
            if let currentIndex = sortedDetents.firstIndex(of: currentDetent) {
                if velocity < 0 {
                    // Swiping up → expand
                    targetDetent = sortedDetents[min(currentIndex + 1, sortedDetents.count - 1)]
                } else {
                    // Swiping down → collapse
                    targetDetent = sortedDetents[max(currentIndex - 1, 0)]
                }
            } else {
                targetDetent = closestDetent(to: currentHeight, in: containerView)
            }
        } else {
            targetDetent = closestDetent(to: currentHeight, in: containerView)
        }

        snapToDetent(targetDetent, in: containerView)
    }

    private func closestDetent(to height: CGFloat, in containerView: UIView) -> DrawerDetent {
        DrawerDetent.allCases.min(by: {
            abs($0.height(in: containerView) - height) < abs($1.height(in: containerView) - height)
        }) ?? .small
    }

    func snapToDetent(_ detent: DrawerDetent, in containerView: UIView? = nil, animated: Bool = true) {
        currentDetent = detent
        guard let container = containerView ?? view.superview else { return }
        let targetHeight = detent.height(in: container)

        if animated {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: .curveEaseInOut
            ) {
                self.heightConstraint.constant = targetHeight
                container.layoutIfNeeded()
            }
        } else {
            heightConstraint.constant = targetHeight
            container.layoutIfNeeded()
        }
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

// MARK: - UIGestureRecognizerDelegate

extension HomeDrawerViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer == collectionView.panGestureRecognizer
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)

        // Only handle vertical drags
        guard abs(velocity.y) > abs(velocity.x) else { return false }

        let isScrolledToTop = collectionView.contentOffset.y <= 0
        let isDraggingDown = velocity.y > 0

        if currentDetent == .large {
            // At large: only begin drawer drag if scrolled to top and dragging down
            return isScrolledToTop && isDraggingDown
        } else {
            // At small/medium: always handle drawer drag when scrolled to top
            return isScrolledToTop
        }
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
