import UIKit
import ARKit
import RealityKit
import AVFoundation
import Combine
import OSLog

private let logger = Logger(subsystem: "nav.parking", category: "ParkingFinder")

/// 스캔 등록/되찾기 공용 AR 화면 (R9).
/// OCR·raycast·사진 캡처 등 뷰 의존 작업을 수행하고 결과를 ParkingARViewModel에 주입한다.
final class ParkingARViewController: UIViewController {

    // MARK: - Callbacks (coordinator 배선)

    var onClose: (() -> Void)?
    var onSaved: ((ParkingSessionRecord) -> Void)?
    var onRequestManualEntry: (() -> Void)?
    var onArrivedConfirm: (() -> Void)?
    var onShowPhotoFallback: (() -> Void)?

    // MARK: - UI

    private let arView = ARView(frame: .zero)

    private let guidanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        return label
    }()

    private let codesLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.footnote
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    private lazy var torchButton = makeRoundButton(systemName: "flashlight.off.fill")
    private lazy var manualButton = makeRoundButton(systemName: "keyboard")
    private lazy var photoButton = makeRoundButton(systemName: "photo")
    private lazy var closeButton = makeRoundButton(systemName: "xmark")

    // find HUD (T025) — GuidanceState의 순수 함수
    private let arrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "location.north.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private let guidanceInfoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    private let bannerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.subheadline
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.85)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    private let arrivedOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        view.isHidden = true
        return view
    }()

    private let arrivedLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let arrivedConfirmButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "✓ 찾았어요"
        config.baseBackgroundColor = Theme.Colors.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let manualSuggestionButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "인식이 어려워요 — 직접 입력하기"
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.7)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    // MARK: - Properties

    private let viewModel: ParkingARViewModel
    private let scanner = CodeScannerService()
    private var cancellables = Set<AnyCancellable>()
    private var torchOn = false
    private var frameCounter = 0

    // 디버그 도구 (DR-001/002/003) — 토글 off면 전부 nil = 비용 0 (DR-005)
    private var debugOverlay: ParkingDebugOverlayView?
    private var debugEntities: ParkingDebugEntities?
    private var arDebugOptionsOn = false

    init(viewModel: ParkingARViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        scanner.onRecognitions = { [weak self] recognitions in
            self?.handleRecognitions(recognitions)
        }
        viewModel.capturePhoto = { [weak self] in
            self?.captureCurrentFramePhoto()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSessionIfAuthorized()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
        setTorch(on: false)
        viewModel.cancelTasks()
        viewModel.recorder?.sessionEnd(by: "screen-exit")
        viewModel.recorder = nil
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black
        arView.frame = view.bounds
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        view.addSubview(guidanceLabel)
        view.addSubview(codesLabel)
        view.addSubview(bannerLabel)
        view.addSubview(arrowImageView)
        view.addSubview(guidanceInfoLabel)
        view.addSubview(closeButton)
        view.addSubview(torchButton)
        view.addSubview(manualButton)
        view.addSubview(photoButton)
        view.addSubview(manualSuggestionButton)
        view.addSubview(arrivedOverlay)
        arrivedOverlay.addSubview(arrivedLabel)
        arrivedOverlay.addSubview(arrivedConfirmButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.lg),

            guidanceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.sm),
            guidanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guidanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: Theme.Spacing.sm),
            guidanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            guidanceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),

            codesLabel.topAnchor.constraint(equalTo: guidanceLabel.bottomAnchor, constant: Theme.Spacing.sm),
            codesLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            codesLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            codesLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            torchButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.xl),
            torchButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.xl),

            manualButton.bottomAnchor.constraint(equalTo: torchButton.bottomAnchor),
            manualButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.xl),

            manualSuggestionButton.bottomAnchor.constraint(equalTo: torchButton.topAnchor, constant: -Theme.Spacing.lg),
            manualSuggestionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            photoButton.bottomAnchor.constraint(equalTo: torchButton.bottomAnchor),
            photoButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.xl),

            bannerLabel.topAnchor.constraint(equalTo: codesLabel.bottomAnchor, constant: Theme.Spacing.sm),
            bannerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            bannerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            arrowImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            arrowImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            arrowImageView.widthAnchor.constraint(equalToConstant: 96),
            arrowImageView.heightAnchor.constraint(equalToConstant: 96),

            guidanceInfoLabel.topAnchor.constraint(equalTo: arrowImageView.bottomAnchor, constant: Theme.Spacing.md),
            guidanceInfoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guidanceInfoLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            guidanceInfoLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            arrivedOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            arrivedOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arrivedOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arrivedOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arrivedLabel.centerXAnchor.constraint(equalTo: arrivedOverlay.centerXAnchor),
            arrivedLabel.centerYAnchor.constraint(equalTo: arrivedOverlay.centerYAnchor, constant: -40),
            arrivedConfirmButton.topAnchor.constraint(equalTo: arrivedLabel.bottomAnchor, constant: Theme.Spacing.xl),
            arrivedConfirmButton.centerXAnchor.constraint(equalTo: arrivedOverlay.centerXAnchor),
        ])

        guidanceLabel.text = "  주변 기둥의 위치 표지판을 비춰주세요  "
        manualButton.isHidden = !isScanMode
        photoButton.isHidden = isScanMode

        closeButton.addAction(UIAction { [weak self] _ in self?.handleClose() }, for: .touchUpInside)
        torchButton.addAction(UIAction { [weak self] _ in self?.toggleTorch() }, for: .touchUpInside)
        manualButton.addAction(UIAction { [weak self] _ in self?.onRequestManualEntry?() }, for: .touchUpInside)
        manualSuggestionButton.addAction(UIAction { [weak self] _ in self?.onRequestManualEntry?() }, for: .touchUpInside)
        photoButton.addAction(UIAction { [weak self] _ in self?.onShowPhotoFallback?() }, for: .touchUpInside)
        arrivedConfirmButton.addAction(UIAction { [weak self] _ in self?.onArrivedConfirm?() }, for: .touchUpInside)

        // 히든 제스처: 상단 안내 문구 5회 탭 → 디버그 토글 (DR-005, T037 — 첫 등록처럼 허브를 안 거치는 흐름 대응)
        let debugTap = UITapGestureRecognizer(target: self, action: #selector(debugGestureFired))
        debugTap.numberOfTapsRequired = 5
        guidanceLabel.isUserInteractionEnabled = true
        guidanceLabel.addGestureRecognizer(debugTap)
    }

    @objc private func debugGestureFired() {
        let enabled = !DevToolsSettings.shared.parkingDebugEnabled.value
        DevToolsSettings.shared.setParkingDebugEnabled(enabled)
        bannerLabel.text = "  주차 디버그 \(enabled ? "ON" : "OFF")  "
        bannerLabel.isHidden = false
        UIView.animate(withDuration: 0.3, delay: 1.5, options: []) {
            self.bannerLabel.alpha = 0
        } completion: { _ in
            self.bannerLabel.isHidden = true
            self.bannerLabel.alpha = 1
        }
    }

    private var isScanMode: Bool {
        if case .scan = viewModel.mode { return true }
        return false
    }

    private func bindViewModel() {
        viewModel.confirmedCodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] codes in
                guard let self else { return }
                self.codesLabel.isHidden = codes.isEmpty
                self.codesLabel.text = "  읽음: \(codes.joined(separator: ", "))  "
            }
            .store(in: &cancellables)

        viewModel.onNeedsFloorInput = { [weak self] pending in
            self?.presentFloorSheet(for: pending)
        }
        viewModel.onSaved = { [weak self] record in
            self?.onSaved?(record)
        }
        viewModel.onSuggestManualEntry = { [weak self] in
            guard let self, self.isScanMode else { return }
            self.manualSuggestionButton.isHidden = false
        }

        viewModel.guidanceState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.renderGuidance(state)
            }
            .store(in: &cancellables)

        viewModel.banner
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] banner in
                self?.showBanner(banner)
            }
            .store(in: &cancellables)

        DevToolsSettings.shared.parkingDebugEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setDebugEnabled(enabled)
            }
            .store(in: &cancellables)
    }

    // MARK: - Debug (DR-001/002/003/005)

    private func setDebugEnabled(_ enabled: Bool) {
        if enabled {
            guard debugOverlay == nil else { return }
            let overlay = ParkingDebugOverlayView(frame: view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.onToggleARDebugOptions = { [weak self] in self?.toggleARDebugOptions() }
            view.insertSubview(overlay, belowSubview: closeButton)
            debugOverlay = overlay
            debugEntities = ParkingDebugEntities(arView: arView)

            viewModel.debugStrip
                .receive(on: DispatchQueue.main)
                .sink { [weak overlay] text in overlay?.updateStrip(text) }
                .store(in: &cancellables)

            startRecorderIfNeeded()
        } else {
            viewModel.recorder?.sessionEnd(by: "debug-off")
            viewModel.recorder = nil
            debugOverlay?.removeFromSuperview()
            debugOverlay = nil
            debugEntities?.removeAll()
            debugEntities = nil
            arView.debugOptions = []
            arDebugOptionsOn = false
        }
    }

    private func startRecorderIfNeeded() {
        guard viewModel.recorder == nil, viewModel.isDebugEnabled else { return }
        switch viewModel.mode {
        case .scan:
            viewModel.recorder = ParkingEventRecorder(mode: "scan", target: nil)
        case .find(let record):
            viewModel.recorder = ParkingEventRecorder(mode: "find", target: record)
        }
    }

    private func toggleARDebugOptions() {
        arDebugOptionsOn.toggle()
        arView.debugOptions = arDebugOptionsOn ? [.showFeaturePoints, .showWorldOrigin] : []
    }

    private func updateDebugEntities() {
        guard let debugEntities else { return }
        debugEntities.syncCodeLabels(viewModel.observations)
        if let estimate = viewModel.lastEstimate {
            let referenceY = (arView.session.currentFrame?.camera.transform.columns.3.y ?? 0) - 1.0
            debugEntities.updateTarget(estimate.targetPosition, referenceY: referenceY)
            debugEntities.updateModel(estimate: estimate, observations: viewModel.observations)
        }
    }

    // MARK: - Find HUD (T025/T026) — GuidanceState의 순수 함수

    private func renderGuidance(_ state: ParkingARViewModel.GuidanceState) {
        guard !isScanMode else { return }
        let targetCode: String = {
            if case .find(let record) = viewModel.mode { return record.targetCodeRaw }
            return ""
        }()

        arrowImageView.isHidden = true
        guidanceInfoLabel.isHidden = true
        arrivedOverlay.isHidden = true

        switch state {
        case .searching:
            guidanceLabel.text = "  \(targetCode) · 주변 기둥을 비춰주세요  "

        case .needMore(let message):
            guidanceLabel.text = "  \(message)  "

        case .guiding(let stageLabel, let arrowRadians, let distance, let confidence):
            guidanceLabel.text = "  \(targetCode) 찾는 중  "
            arrowImageView.isHidden = false
            arrowImageView.transform = CGAffineTransform(rotationAngle: arrowRadians)
            guidanceInfoLabel.isHidden = false
            let dots = ["●○○", "●●○", "●●●"][confidence.rawValue]
            guidanceInfoLabel.text = "  ~\(Int(distance.rounded()))m 이 방향\n\(stageLabel) · 신뢰도 \(dots)  "

        case .degraded(_, let hint):
            if let hint {
                guidanceLabel.text = "  \(hint)  "
                guidanceInfoLabel.isHidden = false
                guidanceInfoLabel.text = "  배치가 불규칙해 방향 대신\n번호 힌트로 안내 중  "
            } else {
                guidanceLabel.text = "  번호 배치가 불규칙해요\n주변 기둥에서 \(targetCode) 를 직접 확인하세요  "
            }

        case .arrived:
            arrivedOverlay.isHidden = false
            arrivedLabel.text = "🎉 도착!\n\(targetCode)"
            setTorch(on: false)
        }
    }

    private func showBanner(_ banner: ParkingARViewModel.Banner) {
        let text: String
        switch banner {
        case .floorMismatch(let message): text = "  \(message)  "
        case .trackingLimited: text = "  천천히 움직여주세요  "
        case .anchorFailing: text = "  기둥에 더 가까이 가거나 손전등을 켜보세요  "
        }
        bannerLabel.text = text
        bannerLabel.isHidden = false
        UIView.animate(withDuration: 0.3, delay: 3.5, options: []) {
            self.bannerLabel.alpha = 0
        } completion: { _ in
            self.bannerLabel.isHidden = true
            self.bannerLabel.alpha = 1
        }
    }

    // MARK: - AR Session

    private func startSessionIfAuthorized() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.runSession()
                    } else {
                        self?.onRequestManualEntry?()   // 거부 → 수동 폴백 (FR-017)
                    }
                }
            }
        default:
            onRequestManualEntry?()
        }
    }

    private func runSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            // 시뮬레이터 등 AR 미지원 환경 → 수동 입력 폴백
            logger.info("[ParkingFinder] AR unsupported on this device → manual entry")
            onRequestManualEntry?()
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.vertical]
        arView.session.delegate = self
        arView.session.run(configuration)
        viewModel.sessionDidStart()
        startRecorderIfNeeded()
        logger.info("[ParkingFinder] AR session start mode=\(self.isScanMode ? "scan" : "find")")
    }

    private func handleFrame(_ frame: ARFrame) {
        scanner.process(frame: frame)

        guard !isScanMode else { return }
        frameCounter += 1
        if frameCounter % 6 == 0 {   // 화살표 갱신 ~10Hz
            let transform = frame.camera.transform
            let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let forward = -simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            viewModel.updateDevicePose(position: position, forward: forward)
            debugEntities?.addTrailPoint(position)
        }
    }

    private func handleRecognitions(_ recognitions: [CodeScannerService.Recognition]) {
        guard let frame = arView.session.currentFrame else { return }
        for recognition in recognitions {
            let position = raycastPosition(for: recognition.boundingBox, frame: frame)
            let verdict = viewModel.addRecognition(
                text: recognition.text,
                confidence: recognition.confidence,
                position: position
            )
            if let debugOverlay {
                let rect = viewRect(for: recognition.boundingBox, frame: frame)
                switch verdict {
                case .accepted, .arrivalProgress:
                    debugOverlay.flashBox(rect, accepted: true, reason: nil)
                case .rejected(let reason):
                    debugOverlay.flashBox(rect, accepted: false, reason: reason)
                case .ignored:
                    break
                }
            }
        }
        if debugEntities != nil {
            updateDebugEntities()
        }
    }

    /// Vision 정규 bbox → 화면 rect (인식 박스 표시용) — raycastPosition과 동일 변환
    private func viewRect(for boundingBox: CGRect, frame: ARFrame) -> CGRect {
        let viewportSize = arView.bounds.size
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let corner1 = CGPoint(x: 1 - boundingBox.maxY, y: 1 - boundingBox.maxX).applying(transform)
        let corner2 = CGPoint(x: 1 - boundingBox.minY, y: 1 - boundingBox.minX).applying(transform)
        let origin = CGPoint(
            x: min(corner1.x, corner2.x) * viewportSize.width,
            y: min(corner1.y, corner2.y) * viewportSize.height
        )
        let size = CGSize(
            width: abs(corner1.x - corner2.x) * viewportSize.width,
            height: abs(corner1.y - corner2.y) * viewportSize.height
        )
        return CGRect(origin: origin, size: size)
    }

    /// Vision 정규 bbox(세로 방향 이미지, 원점 좌하단) 중심 → 화면 좌표 → raycast.
    /// displayTransform은 원본(가로) 카메라 이미지의 정규 좌표(원점 좌상단)를 기대하므로
    /// .right 회전을 역변환해 넘긴다. 이 화면은 portrait 고정 전제.
    private func raycastPosition(for boundingBox: CGRect, frame: ARFrame) -> simd_float3? {
        let imagePoint = CGPoint(x: 1 - boundingBox.midY, y: 1 - boundingBox.midX)
        let viewportSize = arView.bounds.size
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let normalized = imagePoint.applying(transform)
        let viewPoint = CGPoint(x: normalized.x * viewportSize.width, y: normalized.y * viewportSize.height)

        guard arView.bounds.contains(viewPoint) else { return nil }

        if let result = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .vertical).first
            ?? arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any).first {
            let t = result.worldTransform.columns.3
            return simd_float3(t.x, t.y, t.z)
        }
        logger.debug("[ParkingFinder] raycast failed for viewPoint=\(viewPoint.debugDescription)")
        return nil
    }

    // MARK: - Floor Sheet (FR-005)

    private func presentFloorSheet(for pending: ParkingARViewModel.PendingSave) {
        let sheet = UIAlertController(
            title: "몇 층에 주차하셨나요?",
            message: "\(pending.targetCode) 표지판에는 층 정보가 없어요.",
            preferredStyle: .actionSheet
        )
        for floor in ["B1", "B2", "B3", "B4", "B5"] {
            sheet.addAction(UIAlertAction(title: floor, style: .default) { [weak self] _ in
                self?.viewModel.setManualFloor(floor)
            })
        }
        sheet.addAction(UIAlertAction(title: "모름", style: .default) { [weak self] _ in
            self?.viewModel.setManualFloor(nil)
        })
        present(sheet, animated: true)
    }

    // MARK: - Photo (T015)

    /// 코드 확정 순간의 프레임을 JPEG로 저장 → Documents 상대 경로 반환
    private func captureCurrentFramePhoto() -> String? {
        guard let frame = arView.session.currentFrame else { return nil }
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let context = CIContext()
        guard let data = context.jpegRepresentation(
            of: ciImage,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [:]
        ) else { return nil }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ParkingPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let relativePath = "ParkingPhotos/\(UUID().uuidString).jpg"
        do {
            try data.write(to: docs.appendingPathComponent(relativePath))
            return relativePath
        } catch {
            logger.error("[ParkingFinder] photo save failed: \(error)")
            return nil
        }
    }

    // MARK: - Torch (FR-018)

    private func toggleTorch() {
        setTorch(on: !torchOn)
    }

    private func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
            torchButton.configuration?.image = UIImage(
                systemName: on ? "flashlight.on.fill" : "flashlight.off.fill"
            )
        } catch {
            logger.error("[ParkingFinder] torch failed: \(error)")
        }
    }

    // MARK: - Close (T020)

    private func handleClose() {
        guard viewModel.hasUnsavedInput else {
            onClose?()
            return
        }
        let alert = UIAlertController(
            title: "저장하지 않고 나갈까요?",
            message: "인식된 기둥 코드가 저장되지 않았어요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "계속 스캔", style: .cancel))
        alert.addAction(UIAlertAction(title: "나가기", style: .destructive) { [weak self] _ in
            self?.onClose?()
        })
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func makeRoundButton(systemName: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: systemName)
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

// MARK: - ARSessionDelegate (nonisolated + MainActor 홉 — 프로젝트 표준 패턴)

extension ParkingARViewController: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // ARSession delegateQueue 기본값은 메인 큐
        MainActor.assumeIsolated {
            handleFrame(frame)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            logger.info("[ParkingFinder] AR session interrupted")
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        MainActor.assumeIsolated {
            if case .limited = camera.trackingState {
                logger.info("[ParkingFinder] tracking limited")
                viewModel.reportTrackingLimited()
            }
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            // 좌표계 신뢰 불가 — 관측 리셋 후 재시작 (스펙 엣지: 백그라운드 복귀)
            viewModel.invalidateObservations()
            viewModel.sessionDidStart()
            guidanceLabel.text = "  다시 주변을 비춰주세요  "
        }
    }
}
