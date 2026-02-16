import UIKit
import Combine

/// Overlay control bar for virtual drive playback (play/pause, stop, speed)
final class VirtualDriveControlView: UIView {

    // MARK: - Callbacks

    var onPlayPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onSpeedCycle: (() -> Void)?

    // MARK: - UI

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 16
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()

    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        button.setImage(UIImage(systemName: "play.fill")?.withConfiguration(config), for: .normal)
        button.tintColor = .white
        return button
    }()

    private let stopButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "stop.fill")?.withConfiguration(config), for: .normal)
        button.tintColor = .white
        return button
    }()

    private let speedButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("1.0x", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.tintColor = .white
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
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progress.progressTintColor = .systemGreen
        return progress
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.text = "가상 주행"
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
        backgroundColor = UIColor.black.withAlphaComponent(0.85)
        layer.cornerRadius = 16

        addSubview(statusLabel)
        addSubview(progressView)
        addSubview(containerStack)

        containerStack.addArrangedSubview(stopButton)
        containerStack.addArrangedSubview(playPauseButton)
        containerStack.addArrangedSubview(speedButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            containerStack.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 10),
            containerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            playPauseButton.widthAnchor.constraint(equalToConstant: 44),
            playPauseButton.heightAnchor.constraint(equalToConstant: 44),
            stopButton.widthAnchor.constraint(equalToConstant: 44),
            stopButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupActions() {
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)
    }

    // MARK: - Bind to Engine

    func bind(to engine: VirtualDriveEngine) {
        cancellables.removeAll()

        engine.playStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updatePlayPauseIcon(state: state)
                self?.updateStatusLabel(state: state)
            }
            .store(in: &cancellables)

        engine.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.setProgress(Float(progress), animated: true)
            }
            .store(in: &cancellables)

        engine.speedMultiplierPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] multiplier in
                self?.speedButton.setTitle(String(format: "%.1fx", multiplier), for: .normal)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update UI

    private func updatePlayPauseIcon(state: VirtualDriveEngine.PlayState) {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let iconName: String

        switch state {
        case .playing:
            iconName = "pause.fill"
        case .idle, .paused, .finished:
            iconName = "play.fill"
        }

        playPauseButton.setImage(
            UIImage(systemName: iconName)?.withConfiguration(config),
            for: .normal
        )
    }

    private func updateStatusLabel(state: VirtualDriveEngine.PlayState) {
        switch state {
        case .idle:
            statusLabel.text = "가상 주행"
        case .playing:
            statusLabel.text = "가상 주행 중"
        case .paused:
            statusLabel.text = "일시정지"
        case .finished:
            statusLabel.text = "주행 완료"
        }
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
