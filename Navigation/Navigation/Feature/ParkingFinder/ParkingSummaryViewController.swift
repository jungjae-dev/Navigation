import UIKit
import Combine

/// 허브(요약 카드) — 저장 확인·폴백·모든 흐름의 출입구 (FR-001a/016, UI 계약).
final class ParkingSummaryViewController: UIViewController {

    // MARK: - Callbacks

    var onStartGuidance: ((ParkingSessionRecord) -> Void)?
    var onNewRegistration: (() -> Void)?
    var onCompleted: (() -> Void)?
    var onShowPhoto: ((URL) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private let codeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 44, weight: .bold)
        label.textColor = Theme.Colors.label
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.subheadline
        label.textColor = Theme.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = Theme.Colors.secondaryBackground
        imageView.isUserInteractionEnabled = true
        return imageView
    }()

    private let swapPromptLabel: UILabel = {
        let label = UILabel()
        label.font = Theme.Fonts.footnote
        label.textColor = Theme.Colors.secondaryLabel
        label.textAlignment = .center
        label.text = "함께 인식된 기둥 — 내 기둥이 아니면 선택해 바꿔주세요"
        return label
    }()

    private let swapStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Theme.Spacing.sm
        stack.distribution = .fillEqually
        return stack
    }()

    private let startButton = DrawerActionButton(style: .primary, title: "안내 시작", iconName: "location.north.line.fill")
    private let foundButton = DrawerActionButton(style: .secondary, title: "찾았어요", iconName: "checkmark")
    private let newButton = DrawerActionButton(style: .secondary, title: "새 위치 등록")

    // MARK: - Properties

    private let viewModel: ParkingFinderViewModel
    private let justSaved: Bool
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: ParkingFinderViewModel, justSaved: Bool = false) {
        self.viewModel = viewModel
        self.justSaved = justSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        render()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background
        navigationItem.title = "내 차 위치"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.onClose?() }
        )

        let buttonRow = UIStackView(arrangedSubviews: [foundButton, newButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = Theme.Spacing.md
        buttonRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, photoImageView, codeLabel, detailLabel,
            swapPromptLabel, swapStack, startButton, buttonRow,
        ])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.lg
        stack.setCustomSpacing(Theme.Spacing.sm, after: codeLabel)
        stack.setCustomSpacing(Theme.Spacing.sm, after: swapPromptLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.xl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.xl),
            photoImageView.heightAnchor.constraint(equalToConstant: 180),
            startButton.heightAnchor.constraint(equalToConstant: 52),
            foundButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        photoImageView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(photoTapped))
        )
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        foundButton.addTarget(self, action: #selector(foundTapped), for: .touchUpInside)
        newButton.addTarget(self, action: #selector(newTapped), for: .touchUpInside)
    }

    private func bindViewModel() {
        viewModel.activeSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
    }

    // MARK: - Render

    private func render() {
        guard let record = viewModel.activeSession.value else { return }

        titleLabel.text = justSaved ? "✓ 저장되었습니다" : "주차 위치"
        titleLabel.textColor = justSaved ? Theme.Colors.success : Theme.Colors.secondaryLabel
        codeLabel.text = record.targetCodeRaw

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        let elapsed = formatter.localizedString(for: record.createdAt, relativeTo: Date())
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ko_KR")
        timeFormatter.dateFormat = "a h:mm"
        var detail = "\(elapsed) 주차 · \(timeFormatter.string(from: record.createdAt))"
        if let floor = record.floorToken {
            detail = "\(floor)층 · " + detail
        }
        detailLabel.text = detail

        if let photoURL = record.photoURLs.first,
           let image = UIImage(contentsOfFile: photoURL.path) {
            photoImageView.image = image
            photoImageView.isHidden = false
        } else {
            photoImageView.isHidden = true
        }

        renderSwapCandidates(record)
    }

    /// 저장 직후 목표 즉시 교체 UI (FR-002a) — 확인 강제 없음, 재스캔 불필요
    private func renderSwapCandidates(_ record: ParkingSessionRecord) {
        swapStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let show = justSaved && !record.neighbors.isEmpty
        swapPromptLabel.isHidden = !show
        swapStack.isHidden = !show
        guard show else { return }

        for neighbor in record.neighbors.prefix(3) {
            var config = UIButton.Configuration.tinted()
            config.title = neighbor.codeRaw
            config.baseForegroundColor = Theme.Colors.accent
            config.cornerStyle = .medium
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                self?.viewModel.swapTarget(to: neighbor)
            }, for: .touchUpInside)
            swapStack.addArrangedSubview(button)
        }
    }

    // MARK: - Actions

    @objc private func photoTapped() {
        guard let url = viewModel.activeSession.value?.photoURLs.first else { return }
        onShowPhoto?(url)
    }

    @objc private func startTapped() {
        guard let record = viewModel.activeSession.value else { return }
        onStartGuidance?(record)
    }

    @objc private func foundTapped() {
        viewModel.complete(by: "manual")
        onCompleted?()
    }

    @objc private func newTapped() {
        let alert = UIAlertController(
            title: "새 위치를 등록할까요?",
            message: "기존 주차 기록(\(viewModel.activeSession.value?.targetCodeRaw ?? ""))은 새 기록으로 대체됩니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "새로 등록", style: .default) { [weak self] _ in
            self?.onNewRegistration?()
        })
        present(alert, animated: true)
    }
}
