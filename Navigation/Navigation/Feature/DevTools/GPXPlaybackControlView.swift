import UIKit
import Combine

final class GPXPlaybackControlView: UIView {

    // MARK: - Callbacks

    var onPlayPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onSpeedCycle: (() -> Void)?

    // MARK: - UI

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }()

    private let playPauseButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: config)
        button.tintColor = Theme.Colors.primary
        return button
    }()

    private let stopButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: config)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        button.setImage(UIImage(systemName: "stop.fill")?.withConfiguration(symbolConfig), for: .normal)
        button.tintColor = Theme.Colors.destructive
        return button
    }()

    private let speedButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        let button = UIButton(configuration: config)
        button.setTitle("1.0x", for: .normal)
        button.titleLabel?.font = Theme.Fonts.headline
        button.tintColor = Theme.Colors.label
        return button
    }()

    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.trackTintColor = Theme.Colors.separator
        progress.progressTintColor = Theme.Colors.primary
        return progress
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.caption
        label.textColor = Theme.Colors.secondaryLabel
        label.text = "GPX 재생"
        return label
    }()

    // MARK: - Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Theme.Colors.secondaryBackground
        layer.cornerRadius = Theme.CornerRadius.medium
        layer.shadowColor = Theme.Shadow.color
        layer.shadowOpacity = Theme.Shadow.opacity
        layer.shadowOffset = Theme.Shadow.offset
        layer.shadowRadius = Theme.Shadow.radius

        addSubview(statusLabel)
        addSubview(progressView)
        addSubview(containerStack)

        containerStack.addArrangedSubview(playPauseButton)
        containerStack.addArrangedSubview(stopButton)
        containerStack.addArrangedSubview(UIView()) // spacer
        containerStack.addArrangedSubview(speedButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.sm),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.lg),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Theme.Spacing.sm),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.lg),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.lg),

            containerStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: Theme.Spacing.sm),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.lg),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.lg),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.sm),
            containerStack.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupActions() {
        playPauseButton.addAction(UIAction { [weak self] _ in
            self?.onPlayPause?()
        }, for: .touchUpInside)

        stopButton.addAction(UIAction { [weak self] _ in
            self?.onStop?()
        }, for: .touchUpInside)

        speedButton.addAction(UIAction { [weak self] _ in
            self?.onSpeedCycle?()
        }, for: .touchUpInside)
    }

    // MARK: - Bind

    func bind(to simulator: GPXSimulator) {
        cancellables.removeAll()

        simulator.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                let iconName = isPlaying ? "pause.fill" : "play.fill"
                let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
                self?.playPauseButton.setImage(
                    UIImage(systemName: iconName)?.withConfiguration(config),
                    for: .normal
                )
                self?.statusLabel.text = isPlaying ? "GPX 재생 중" : "GPX 재생"
            }
            .store(in: &cancellables)

        simulator.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.setProgress(Float(progress), animated: true)
            }
            .store(in: &cancellables)

        simulator.speedMultiplierPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] multiplier in
                self?.speedButton.setTitle(String(format: "%.1fx", multiplier), for: .normal)
            }
            .store(in: &cancellables)
    }
}
