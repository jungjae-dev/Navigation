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
    private lazy var closeButton = makeRoundButton(systemName: "xmark")

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
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black
        arView.frame = view.bounds
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        view.addSubview(guidanceLabel)
        view.addSubview(codesLabel)
        view.addSubview(closeButton)
        view.addSubview(torchButton)
        view.addSubview(manualButton)
        view.addSubview(manualSuggestionButton)

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
        ])

        guidanceLabel.text = "  주변 기둥의 위치 표지판을 비춰주세요  "
        manualButton.isHidden = !isScanMode

        closeButton.addAction(UIAction { [weak self] _ in self?.handleClose() }, for: .touchUpInside)
        torchButton.addAction(UIAction { [weak self] _ in self?.toggleTorch() }, for: .touchUpInside)
        manualButton.addAction(UIAction { [weak self] _ in self?.onRequestManualEntry?() }, for: .touchUpInside)
        manualSuggestionButton.addAction(UIAction { [weak self] _ in self?.onRequestManualEntry?() }, for: .touchUpInside)
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
        logger.info("[ParkingFinder] AR session start mode=\(self.isScanMode ? "scan" : "find")")
    }

    private func handleFrame(_ frame: ARFrame) {
        scanner.process(frame: frame)
    }

    private func handleRecognitions(_ recognitions: [CodeScannerService.Recognition]) {
        guard let frame = arView.session.currentFrame else { return }
        for recognition in recognitions {
            let position = raycastPosition(for: recognition.boundingBox, frame: frame)
            viewModel.addRecognition(
                text: recognition.text,
                confidence: recognition.confidence,
                position: position
            )
        }
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

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            // 좌표계 신뢰 불가 — 관측 리셋 후 재시작 (스펙 엣지: 백그라운드 복귀)
            viewModel.invalidateObservations()
            viewModel.sessionDidStart()
            guidanceLabel.text = "  다시 주변을 비춰주세요  "
        }
    }
}
