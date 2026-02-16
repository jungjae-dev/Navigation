import UIKit
import Combine
import MapKit

final class NavigationViewController: UIViewController {

    // MARK: - UI Components

    private let maneuverBanner = ManeuverBannerView()
    private let bottomBar = NavigationBottomBar()

    private let recenterButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "location.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)),
            for: .normal
        )
        button.tintColor = Theme.Colors.primary
        button.backgroundColor = Theme.Colors.background
        button.layer.cornerRadius = 24
        button.layer.shadowColor = Theme.Shadow.color
        button.layer.shadowOpacity = Theme.Shadow.opacity
        button.layer.shadowOffset = Theme.Shadow.offset
        button.layer.shadowRadius = Theme.Shadow.radius
        button.isHidden = true
        return button
    }()

    // MARK: - Properties

    private let viewModel: NavigationViewModel
    private let mapViewController: MapViewController
    private let turnPointPopupService: TurnPointPopupService
    private var cancellables = Set<AnyCancellable>()
    private var turnPointPopupView: TurnPointPopupView?

    var onDismiss: (() -> Void)?

    // MARK: - Init

    init(
        viewModel: NavigationViewModel,
        mapViewController: MapViewController,
        turnPointPopupService: TurnPointPopupService
    ) {
        self.viewModel = viewModel
        self.mapViewController = mapViewController
        self.turnPointPopupService = turnPointPopupService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapChild()
        setupOverlayUI()
        setupActions()
        bindViewModel()
        bindPopup()
    }

    // MARK: - Setup

    private func setupMapChild() {
        addChild(mapViewController)
        mapViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapViewController.view)

        NSLayoutConstraint.activate([
            mapViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mapViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        mapViewController.didMove(toParent: self)
    }

    private func setupOverlayUI() {
        maneuverBanner.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(maneuverBanner)
        view.addSubview(bottomBar)
        view.addSubview(recenterButton)

        NSLayoutConstraint.activate([
            // Maneuver banner — top
            maneuverBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            maneuverBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            maneuverBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),

            // Bottom bar
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Recenter button — right side above bottom bar
            recenterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            recenterButton.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -Theme.Spacing.lg),
            recenterButton.widthAnchor.constraint(equalToConstant: 48),
            recenterButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func setupActions() {
        recenterButton.accessibilityLabel = "현재 위치로 이동"
        recenterButton.accessibilityHint = "지도를 현재 위치로 이동합니다"
        recenterButton.addTarget(self, action: #selector(recenterTapped), for: .touchUpInside)

        bottomBar.onEndNavigation = { [weak self] in
            self?.endNavigation()
        }

        mapViewController.onUserInteraction = { [weak self] in
            self?.viewModel.handleUserMapInteraction()
        }
    }

    // MARK: - Binding

    private func bindViewModel() {
        // Maneuver banner
        Publishers.CombineLatest3(
            viewModel.maneuverInstruction,
            viewModel.maneuverDistance,
            viewModel.maneuverIconName
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] instruction, distance, iconName in
            self?.maneuverBanner.update(
                instruction: instruction,
                distance: distance,
                iconName: iconName
            )
        }
        .store(in: &cancellables)

        // Bottom bar
        Publishers.CombineLatest3(
            viewModel.etaText,
            viewModel.remainingDistance,
            viewModel.remainingTime
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] eta, distance, time in
            self?.bottomBar.update(eta: eta, distance: distance, time: time)
        }
        .store(in: &cancellables)

        // Recenter button visibility
        viewModel.showRecenterButton
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                UIView.animate(withDuration: 0.2) {
                    self?.recenterButton.isHidden = !show
                    self?.recenterButton.alpha = show ? 1 : 0
                }
            }
            .store(in: &cancellables)

        // Navigation state
        viewModel.navigationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleNavigationState(state)
            }
            .store(in: &cancellables)

        // Error messages
        viewModel.errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.showErrorToast(message)
            }
            .store(in: &cancellables)
    }

    private func bindPopup() {
        turnPointPopupService.showPopupPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if show {
                    self?.showTurnPointPopup()
                } else {
                    self?.hideTurnPointPopup()
                }
            }
            .store(in: &cancellables)

        turnPointPopupService.popupConfigPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                if self?.turnPointPopupView != nil {
                    self?.turnPointPopupView?.updateVehiclePosition(config.vehicleCoordinate)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Turn Point Popup

    private func showTurnPointPopup() {
        guard turnPointPopupView == nil,
              let config = turnPointPopupService.popupConfigPublisher.value else { return }

        let popup = TurnPointPopupView()
        popup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(popup)

        // Position: bottom-left, 60% × 40% of screen
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            popup.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -Theme.Spacing.lg),
            popup.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.55),
            popup.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35),
        ])

        popup.configure(with: config)
        popup.showAnimated()
        turnPointPopupView = popup
    }

    private func hideTurnPointPopup() {
        turnPointPopupView?.hideAnimated { [weak self] in
            self?.turnPointPopupView?.removeFromSuperview()
            self?.turnPointPopupView = nil
        }
    }

    // MARK: - Navigation State

    private func handleNavigationState(_ state: NavigationState) {
        switch state {
        case .arrived:
            showArrivedAlert()
        case .rerouting:
            maneuverBanner.update(
                instruction: "경로를 재탐색 중입니다...",
                distance: "--",
                iconName: "arrow.triangle.2.circlepath"
            )
        default:
            break
        }
    }

    private func showArrivedAlert() {
        let alert = UIAlertController(
            title: "도착",
            message: "목적지에 도착했습니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.endNavigation()
        })
        present(alert, animated: true)
    }

    // MARK: - Error Toast

    private func showErrorToast(_ message: String) {
        let toastLabel = UILabel()
        toastLabel.text = message
        toastLabel.font = Theme.Fonts.caption
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        toastLabel.layer.cornerRadius = 8
        toastLabel.clipsToBounds = true
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.alpha = 0

        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: maneuverBanner.bottomAnchor, constant: Theme.Spacing.sm),
            toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.Spacing.lg),
            toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Theme.Spacing.lg),
            toastLabel.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Add padding
        toastLabel.layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)

        UIView.animate(withDuration: 0.3) {
            toastLabel.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.3) {
                toastLabel.alpha = 0
            } completion: { _ in
                toastLabel.removeFromSuperview()
            }
        }
    }

    // MARK: - Actions

    @objc private func recenterTapped() {
        viewModel.recenterMap()
    }

    private func endNavigation() {
        viewModel.stopNavigation()
        onDismiss?()
    }
}
