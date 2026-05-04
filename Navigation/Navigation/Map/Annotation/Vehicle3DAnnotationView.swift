import UIKit
import MapKit
import SceneKit

/// 3D 차량 모델을 표시하는 annotation view.
/// 2D 아이콘(image) 위에 SCNView를 올려서 자동추적 모드에서 3D를 표시하고,
/// 수동 모드에서는 SCNView를 숨겨 2D 아이콘이 보이게 함.
final class Vehicle3DAnnotationView: MKAnnotationView {

    private let sceneView = SCNView()
    private var vehicleNode: SCNNode?
    private var rotationSteps: Int = 0

    /// 지도 heading 기준 차량 heading (degrees, 0=북쪽)
    var vehicleHeading: CLLocationDirection = 0 {
        didSet { updateHeading() }
    }

    /// 자동추적 모드에서 true, 수동 모드에서 false
    var is3DVisible: Bool = false {
        didSet { sceneView.isHidden = !is3DVisible }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupSceneView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    func loadModel(fileURL: URL, rotationSteps: Int, pitch: CGFloat) {
        self.rotationSteps = rotationSteps
        guard let scene = try? SCNScene(url: fileURL, options: nil) else { return }
        vehicleNode = scene.rootNode
        sceneView.scene = scene
        setupCamera(pitch: pitch)
        updateHeading()
    }

    // MARK: - Private

    private func setupSceneView() {
        let size: CGFloat = 88
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        sceneView.frame = bounds
        sceneView.backgroundColor = .clear
        sceneView.isUserInteractionEnabled = false
        sceneView.autoenablesDefaultLighting = true
        sceneView.isHidden = true
        addSubview(sceneView)
    }

    private func setupCamera(pitch: CGFloat) {
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera

        let pitchRad = Float(pitch * .pi / 180)
        let distance: Float = 3.0
        cameraNode.position = SCNVector3(0, sin(pitchRad) * distance, cos(pitchRad) * distance)
        cameraNode.look(at: SCNVector3Zero)

        sceneView.scene?.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
    }

    private func updateHeading() {
        let base = Float(rotationSteps) * (.pi / 2)
        let heading = Float(vehicleHeading * .pi / 180)
        vehicleNode?.eulerAngles.y = base + heading
    }
}
