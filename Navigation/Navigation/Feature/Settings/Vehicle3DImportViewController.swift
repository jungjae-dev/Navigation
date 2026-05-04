import UIKit
import SceneKit

/// USDZ 임포트 미리보기 + 방향 보정 UI.
/// 사용자가 90° 단위로 모델 방향을 조정하고 확인하면 completion 호출.
final class Vehicle3DImportViewController: UIViewController {

    // MARK: - Properties

    private let fileURL: URL
    var onConfirm: ((_ fileURL: URL, _ rotationSteps: Int) -> Void)?

    private let sceneView = SCNView()
    private var vehicleNode: SCNNode?
    private var rotationSteps: Int = 0

    // MARK: - Init

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "3D 모델 방향 설정"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupSceneView()
        setupRotationButtons()
        loadModel()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "취소", style: .plain, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "확인", style: .done, target: self, action: #selector(confirmTapped)
        )
    }

    private func setupSceneView() {
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = UIColor.secondarySystemBackground
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = false
        view.addSubview(sceneView)

        let buttonAreaHeight: CGFloat = 120
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -buttonAreaHeight),
        ])
    }

    private func setupRotationButtons() {
        let label = UILabel()
        label.text = "차량 앞면이 화면 위쪽을 향하도록 조정하세요"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let leftButton = UIButton(type: .system)
        leftButton.setImage(UIImage(systemName: "rotate.left"), for: .normal)
        leftButton.setTitle(" 왼쪽 90°", for: .normal)
        leftButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        leftButton.addTarget(self, action: #selector(rotateLeft), for: .touchUpInside)
        leftButton.translatesAutoresizingMaskIntoConstraints = false

        let rightButton = UIButton(type: .system)
        rightButton.setImage(UIImage(systemName: "rotate.right"), for: .normal)
        rightButton.setTitle(" 오른쪽 90°", for: .normal)
        rightButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        rightButton.addTarget(self, action: #selector(rotateRight), for: .touchUpInside)
        rightButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = UIStackView(arrangedSubviews: [leftButton, rightButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 16
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            label.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            buttonStack.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func loadModel() {
        guard let scene = try? SCNScene(url: fileURL, options: nil) else {
            showLoadError()
            return
        }

        vehicleNode = scene.rootNode
        sceneView.scene = scene

        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3, 3)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
    }

    // MARK: - Actions

    @objc private func rotateLeft() {
        rotationSteps = (rotationSteps + 3) % 4  // -1 mod 4
        applyRotation(animated: true)
    }

    @objc private func rotateRight() {
        rotationSteps = (rotationSteps + 1) % 4
        applyRotation(animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func confirmTapped() {
        onConfirm?(fileURL, rotationSteps)
        dismiss(animated: true)
    }

    // MARK: - Private

    private func applyRotation(animated: Bool) {
        let targetAngle = Float(rotationSteps) * (.pi / 2)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            vehicleNode?.eulerAngles.y = targetAngle
            SCNTransaction.commit()
        } else {
            vehicleNode?.eulerAngles.y = targetAngle
        }
    }

    private func showLoadError() {
        let alert = UIAlertController(title: "불러오기 실패", message: "USDZ 파일을 로드할 수 없습니다.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
