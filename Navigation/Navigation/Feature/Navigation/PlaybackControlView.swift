import UIKit
import Combine

/// Unified playback control overlay for virtual drive and GPX playback
final class PlaybackControlView: UIView {

    // MARK: - Callbacks

    var onPlayPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onSpeedCycle: (() -> Void)?

    // MARK: - UI

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = Theme.Spacing.lg
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()

    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: Theme.Playback.iconSize, weight: .semibold)
        button.setImage(UIImage(systemName: "play.fill")?.withConfiguration(config), for: .normal)
        button.tintColor = Theme.Banner.foregroundColor
        return button
    }()

    private let stopButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: Theme.Card.iconSize, weight: .medium)
        button.setImage(UIImage(systemName: "stop.fill")?.withConfiguration(config), for: .normal)
        button.tintColor = Theme.Banner.foregroundColor
        return button
    }()

    private let speedButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("1.0x", for: .normal)
        button.titleLabel?.font = Theme.Playback.speedFont
        button.tintColor = Theme.Banner.foregroundColor
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 8
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        button.configuration = buttonConfig
        return button
    }()

    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.trackTintColor = UIColor.white.withAlphaComponent(Theme.Playback.trackTintOpacity)
        progress.progressTintColor = Theme.Playback.progressColor
        return progress
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Playback.statusFont
        label.textColor = Theme.Playback.statusColor
        label.text = "시뮬레이션"
        return label
    }()

    // MARK: - State

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
        backgroundColor = Theme.Playback.backgroundColor
        layer.cornerRadius = Theme.Playback.cornerRadius

        addSubview(statusLabel)
        addSubview(progressView)
        addSubview(containerStack)

        containerStack.addArrangedSubview(stopButton)
        containerStack.addArrangedSubview(playPauseButton)
        containerStack.addArrangedSubview(speedButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.md),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Theme.Spacing.xs),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Playback.padding),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Playback.padding),

            containerStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: Theme.Spacing.md),
            containerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.md),

            playPauseButton.widthAnchor.constraint(equalToConstant: Theme.Playback.buttonSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: Theme.Playback.buttonSize),
            stopButton.widthAnchor.constraint(equalToConstant: Theme.Playback.buttonSize),
            stopButton.heightAnchor.constraint(equalToConstant: Theme.Playback.buttonSize),
        ])
    }

    private func setupActions() {
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)
    }

    // MARK: - Bind

    func bind(to source: PlaybackControllable) {
        cancellables.removeAll()

        source.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                let iconName = isPlaying ? "pause.fill" : "play.fill"
                let config = UIImage.SymbolConfiguration(pointSize: Theme.Playback.iconSize, weight: .semibold)
                self?.playPauseButton.setImage(
                    UIImage(systemName: iconName)?.withConfiguration(config),
                    for: .normal
                )
                self?.statusLabel.text = isPlaying ? "시뮬레이션 중" : "시뮬레이션"
            }
            .store(in: &cancellables)

        source.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.setProgress(Float(progress), animated: true)
            }
            .store(in: &cancellables)

        source.speedMultiplierPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] multiplier in
                self?.speedButton.setTitle(String(format: "%.1fx", multiplier), for: .normal)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func playPauseTapped() {
        onPlayPause?()
    }

    @objc private func stopTapped() {
        onStop?()
    }

    @objc private func speedTapped() {
        onSpeedCycle?()
    }
}
