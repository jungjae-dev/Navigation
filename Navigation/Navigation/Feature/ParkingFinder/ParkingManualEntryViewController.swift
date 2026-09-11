import UIKit
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "nav.parking", category: "ParkingFinder")

/// 수동 등록 폴백 — 권한 거부·인식 불가 환경의 안전망 (US3, FR-004/017).
/// 저장 결과는 스캔 등록과 동일한 ParkingSessionRecord.
final class ParkingManualEntryViewController: UIViewController {

    var onSaved: ((ParkingSessionRecord) -> Void)?
    var onClose: (() -> Void)?

    // MARK: - UI

    private let codeField: UITextField = {
        let field = UITextField()
        field.placeholder = "기둥 코드 (예: B2-A-3)"
        field.font = UIFont.monospacedSystemFont(ofSize: 28, weight: .semibold)
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let floorLabel: UILabel = {
        let label = UILabel()
        label.text = "층 (코드에 층이 없을 때)"
        label.font = Theme.Fonts.footnote
        label.textColor = Theme.Colors.secondaryLabel
        return label
    }()

    private let floorControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["B1", "B2", "B3", "B4", "B5", "모름"])
        control.selectedSegmentIndex = 5
        return control
    }()

    private let photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = Theme.Colors.secondaryBackground
        imageView.isHidden = true
        return imageView
    }()

    private let photoButton = DrawerActionButton(style: .secondary, title: "주변 사진 추가", iconName: "camera")
    private let saveButton = DrawerActionButton(style: .primary, title: "저장")

    private var attachedPhotoPath: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Colors.background
        navigationItem.title = "주차 위치 직접 입력"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.handleClose() }
        )

        let stack = UIStackView(arrangedSubviews: [
            codeField, floorLabel, floorControl, photoImageView, photoButton, saveButton,
        ])
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.lg
        stack.setCustomSpacing(Theme.Spacing.xs, after: floorLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.xl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.xl),
            codeField.heightAnchor.constraint(equalToConstant: 56),
            photoImageView.heightAnchor.constraint(equalToConstant: 140),
            saveButton.heightAnchor.constraint(equalToConstant: 52),
            photoButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // 카메라 권한이 없으면 사진 첨부 숨김 — 수동 등록·열람은 카메라 없이 완전 동작 (FR-017)
        photoButton.isHidden = AVCaptureDevice.authorizationStatus(for: .video) != .authorized

        photoButton.addTarget(self, action: #selector(attachPhoto), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        codeField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func attachPhoto() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func save() {
        guard let text = codeField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            codeField.layer.borderColor = Theme.Colors.destructive.cgColor
            codeField.layer.borderWidth = 1
            return
        }

        let parsed = PillarCodeParser.parse(text)
        let normalizedRaw = parsed?.raw ?? PillarCodeParser.normalized(text)

        let selectedFloor: String? = {
            let index = floorControl.selectedSegmentIndex
            guard index >= 0, index < 5 else { return nil }
            return floorControl.titleForSegment(at: index)
        }()

        let floorToken = parsed?.floorToken ?? selectedFloor
        let floorSource: ParkingSessionRecord.FloorSource = parsed?.floorToken != nil ? .code : .manual

        // 수동 코드 1개가 스켈레톤 시드 (FR-008). 파싱 불가면 RAW — 되찾기는 근접확인 모드 고정 (FR-016)
        let skeleton = parsed.map { PillarCodeParser.skeleton(fromRegistered: [$0]) }
            ?? PillarCodeParser.rawSkeleton

        let record = ParkingSessionRecord(
            targetCodeRaw: normalizedRaw,
            floorToken: floorToken,
            floorSource: floorSource,
            zoneToken: parsed?.zoneToken,
            numberValue: parsed?.numberValue,
            templateSkeleton: skeleton,
            photoPaths: attachedPhotoPath.map { [$0] } ?? []
        )
        DataService.shared.saveParkingSession(record)
        logger.info("[ParkingFinder] session saved: \(record.targetCodeRaw) floor=\(record.floorToken ?? "?")(\(record.floorSourceRaw)) photos=\(record.photoPaths.count)")
        onSaved?(record)
    }

    private func handleClose() {
        guard let text = codeField.text, !text.isEmpty else {
            onClose?()
            return
        }
        let alert = UIAlertController(
            title: "저장하지 않고 나갈까요?",
            message: "입력한 내용이 저장되지 않았어요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "계속 입력", style: .cancel))
        alert.addAction(UIAlertAction(title: "나가기", style: .destructive) { [weak self] _ in
            self?.deleteAttachedPhotoFile()   // 미저장 이탈 — 촬영본 고아 파일 방지 (PR#49 리뷰)
            self?.onClose?()
        })
        present(alert, animated: true)
    }

    /// 아직 레코드에 귀속되지 않은 첨부 사진 파일 삭제 — 재촬영·미저장 이탈 시 고아 파일 방지
    private func deleteAttachedPhotoFile() {
        guard let path = attachedPhotoPath else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: docs.appendingPathComponent(path))
        attachedPhotoPath = nil
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ParkingManualEntryViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.8) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ParkingPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let relativePath = "ParkingPhotos/\(UUID().uuidString).jpg"
        do {
            try data.write(to: docs.appendingPathComponent(relativePath))
            deleteAttachedPhotoFile()   // 재촬영 시 이전 촬영본 정리 (PR#49 리뷰)
            attachedPhotoPath = relativePath
            photoImageView.image = image
            photoImageView.isHidden = false
        } catch {
            logger.error("[ParkingFinder] manual photo save failed: \(error)")
        }
    }
}
