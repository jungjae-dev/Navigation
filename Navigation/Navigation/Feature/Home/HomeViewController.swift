import UIKit
import Combine

final class HomeViewController: UIViewController {

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

    // MARK: - Properties

    private let viewModel: HomeViewModel
    private let mapViewController: MapViewController
    private var cancellables = Set<AnyCancellable>()

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
        bindViewModel()
        handleInitialPermission()
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
