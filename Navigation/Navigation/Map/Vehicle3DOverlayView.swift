import UIKit
import SceneKit
import Combine
import CoreLocation

/// A SceneKit overlay view that renders a 3D vehicle model synchronized with map heading
final class Vehicle3DOverlayView: UIView {

    // MARK: - Properties

    private let sceneView: SCNView = {
        let view = SCNView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private var vehicleNode: SCNNode?
    private var cameraNode: SCNNode?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration

    private let vehicleSize: CGFloat = 60
    private var currentHeading: CLLocationDirection = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSceneView()
        setupScene()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupSceneView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false

        addSubview(sceneView)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupScene() {
        let scene = SCNScene()
        sceneView.scene = scene

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 45
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3, 5)
        cameraNode.eulerAngles.x = -.pi / 8
        scene.rootNode.addChildNode(cameraNode)
        self.cameraNode = cameraNode

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor(white: 0.6, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        // Directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.castsShadow = true
        directionalLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(directionalLight)

        // Load vehicle model
        loadVehicleModel(into: scene)
    }

    // MARK: - Vehicle Model Loading

    private func loadVehicleModel(into scene: SCNScene) {
        // Try to load USDZ model first
        if let usdzNode = loadUSDZModel() {
            vehicleNode = usdzNode
            scene.rootNode.addChildNode(usdzNode)
            return
        }

        // Fallback: Create a simple car shape with SceneKit primitives
        let carNode = createPrimitiveCar()
        vehicleNode = carNode
        scene.rootNode.addChildNode(carNode)
    }

    private func loadUSDZModel() -> SCNNode? {
        // Check for USDZ model in bundle
        let modelNames = ["sedan", "car", "vehicle"]

        for name in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "usdz") {
                let scene = try? SCNScene(url: url)
                if let rootNode = scene?.rootNode {
                    let containerNode = SCNNode()

                    // Clone all children into container
                    for child in rootNode.childNodes {
                        containerNode.addChildNode(child.clone())
                    }

                    // Normalize size
                    let (min, max) = containerNode.boundingBox
                    let width = CGFloat(max.x - min.x)
                    let depth = CGFloat(max.z - min.z)
                    let maxDim = Swift.max(width, depth)
                    if maxDim > 0 {
                        let scaleFactor = Float(2.0 / maxDim)
                        containerNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                    }

                    // Center
                    let centerX = (min.x + max.x) / 2
                    let centerY = min.y
                    let centerZ = (min.z + max.z) / 2
                    containerNode.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)

                    return containerNode
                }
            }
        }

        return nil
    }

    private func createPrimitiveCar() -> SCNNode {
        let carNode = SCNNode()

        // Body (box)
        let bodyGeometry = SCNBox(width: 1.6, height: 0.5, length: 3.5, chamferRadius: 0.15)
        bodyGeometry.firstMaterial?.diffuse.contents = UIColor.systemBlue
        bodyGeometry.firstMaterial?.metalness.contents = 0.3
        bodyGeometry.firstMaterial?.roughness.contents = 0.4
        let bodyNode = SCNNode(geometry: bodyGeometry)
        bodyNode.position = SCNVector3(0, 0.4, 0)
        carNode.addChildNode(bodyNode)

        // Cabin (smaller box on top)
        let cabinGeometry = SCNBox(width: 1.3, height: 0.5, length: 1.8, chamferRadius: 0.2)
        cabinGeometry.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.8)
        cabinGeometry.firstMaterial?.metalness.contents = 0.5
        let cabinNode = SCNNode(geometry: cabinGeometry)
        cabinNode.position = SCNVector3(0, 0.9, -0.2)
        carNode.addChildNode(cabinNode)

        // Windows (glass material on cabin sides)
        let windowGeometry = SCNBox(width: 1.31, height: 0.35, length: 1.6, chamferRadius: 0.1)
        windowGeometry.firstMaterial?.diffuse.contents = UIColor(white: 0.3, alpha: 0.7)
        windowGeometry.firstMaterial?.transparency = 0.6
        let windowNode = SCNNode(geometry: windowGeometry)
        windowNode.position = SCNVector3(0, 0.95, -0.2)
        carNode.addChildNode(windowNode)

        // Wheels
        let wheelPositions: [(Float, Float)] = [
            (-0.7, 1.1),   // front-left
            (0.7, 1.1),    // front-right
            (-0.7, -1.1),  // rear-left
            (0.7, -1.1),   // rear-right
        ]

        for (x, z) in wheelPositions {
            let wheelGeometry = SCNCylinder(radius: 0.25, height: 0.2)
            wheelGeometry.firstMaterial?.diffuse.contents = UIColor.darkGray
            let wheelNode = SCNNode(geometry: wheelGeometry)
            wheelNode.position = SCNVector3(x, 0.25, z)
            wheelNode.eulerAngles.z = .pi / 2
            carNode.addChildNode(wheelNode)
        }

        // Headlights
        let headlightGeometry = SCNSphere(radius: 0.1)
        headlightGeometry.firstMaterial?.diffuse.contents = UIColor.yellow
        headlightGeometry.firstMaterial?.emission.contents = UIColor.yellow
        for x: Float in [-0.55, 0.55] {
            let lightNode = SCNNode(geometry: headlightGeometry)
            lightNode.position = SCNVector3(x, 0.45, 1.75)
            carNode.addChildNode(lightNode)
        }

        // Scale down
        carNode.scale = SCNVector3(0.5, 0.5, 0.5)

        return carNode
    }

    // MARK: - Public: Update Heading

    /// Update the vehicle's rotation to match map heading
    func updateHeading(_ heading: CLLocationDirection) {
        currentHeading = heading
        let radians = Float(heading) * Float.pi / 180.0
        vehicleNode?.eulerAngles.y = Float(-radians)
    }

    // MARK: - Public: Show/Hide

    func show() {
        isHidden = false
        sceneView.play(nil)
    }

    func hide() {
        isHidden = true
        sceneView.pause(nil)
    }
}
