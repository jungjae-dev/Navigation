import UIKit
import Combine

// MARK: - Vehicle Preset

enum VehiclePreset: String, CaseIterable, Sendable {
    case sedan
    case suv
    case sportsCar
    case truck
    case motorcycle

    var displayName: String {
        switch self {
        case .sedan: return "세단"
        case .suv: return "SUV"
        case .sportsCar: return "스포츠카"
        case .truck: return "트럭"
        case .motorcycle: return "오토바이"
        }
    }

    var iconName: String {
        switch self {
        case .sedan: return "car.fill"
        case .suv: return "car.rear.fill"
        case .sportsCar: return "car.side.fill"
        case .truck: return "truck.box.fill"
        case .motorcycle: return "bicycle"
        }
    }

    /// Returns an SF Symbol image for the vehicle, tinted to the given color
    func image(size: CGFloat = 24, color: UIColor = .systemBlue) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        return UIImage(systemName: iconName)?
            .withConfiguration(config)
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }
}

// MARK: - Vehicle Icon Source

enum VehicleIconSource: Equatable {
    case preset(VehiclePreset)
    case custom(String)   // filename in documents directory
    case model3D(String)  // filename in documents directory

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var isModel3D: Bool {
        if case .model3D = self { return true }
        return false
    }
}

// MARK: - Vehicle Icon Service

/// Manages vehicle icon selection (preset SF Symbols or custom images)
final class VehicleIconService {

    // MARK: - Singleton

    static let shared = VehicleIconService()

    // MARK: - Publishers

    let selectedPresetPublisher = CurrentValueSubject<VehiclePreset, Never>(.sedan)
    let iconSourcePublisher = CurrentValueSubject<VehicleIconSource, Never>(.preset(.sedan))

    // MARK: - Storage

    private let defaults = UserDefaults.standard
    private let presetKey = "settings_vehicle_preset"
    private let customImageKey = "settings_vehicle_custom_image"
    private let model3DKey = "settings_vehicle_3d_filename"
    private let model3DRotationKey = "settings_vehicle_3d_rotation_steps"

    // MARK: - Init

    private init() {
        loadSettings()
    }

    // MARK: - Public: Preset

    var selectedPreset: VehiclePreset {
        selectedPresetPublisher.value
    }

    func selectPreset(_ preset: VehiclePreset) {
        selectedPresetPublisher.send(preset)
        iconSourcePublisher.send(.preset(preset))
        defaults.set(preset.rawValue, forKey: presetKey)
        defaults.removeObject(forKey: customImageKey)
    }

    // MARK: - Public: Custom Image

    func setCustomImage(_ image: UIImage) -> Bool {
        guard let data = image.pngData() else { return false }

        let filename = "vehicle_custom_icon.png"
        let url = documentsDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            defaults.set(filename, forKey: customImageKey)
            iconSourcePublisher.send(.custom(filename))
            return true
        } catch {
            return false
        }
    }

    func loadCustomImage() -> UIImage? {
        guard let filename = defaults.string(forKey: customImageKey) else { return nil }
        let url = documentsDirectory.appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    func clearCustomImage() {
        if let filename = defaults.string(forKey: customImageKey) {
            try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(filename))
        }
        defaults.removeObject(forKey: customImageKey)
        if let model3DFilename = defaults.string(forKey: model3DKey) {
            iconSourcePublisher.send(.model3D(model3DFilename))
        } else {
            iconSourcePublisher.send(.preset(selectedPreset))
        }
    }

    // MARK: - Public: 3D Model

    func setModel3D(fileURL: URL, rotationSteps: Int) -> Bool {
        let filename = "vehicle_3d_model.usdz"
        let dest = documentsDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: fileURL, to: dest)
            defaults.set(filename, forKey: model3DKey)
            defaults.set(rotationSteps, forKey: model3DRotationKey)
            iconSourcePublisher.send(.model3D(filename))
            return true
        } catch {
            return false
        }
    }

    func loadModel3DURL() -> URL? {
        guard let filename = defaults.string(forKey: model3DKey) else { return nil }
        let url = documentsDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func loadModel3DRotationSteps() -> Int {
        defaults.integer(forKey: model3DRotationKey)
    }

    func clearModel3D() {
        if let filename = defaults.string(forKey: model3DKey) {
            try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(filename))
        }
        defaults.removeObject(forKey: model3DKey)
        defaults.removeObject(forKey: model3DRotationKey)
        iconSourcePublisher.send(.preset(selectedPreset))
    }

    // MARK: - Public: Current Icon

    /// Returns the current vehicle icon image (preset or custom)
    func currentVehicleImage(size: CGFloat = 24) -> UIImage? {
        switch iconSourcePublisher.value {
        case .preset(let preset):
            return preset.image(size: size)
        case .custom:
            return loadCustomImage()?.resized(to: CGSize(width: size, height: size))
        case .model3D:
            return nil
        }
    }

    // MARK: - Private

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func loadSettings() {
        let presetRaw = defaults.string(forKey: presetKey) ?? VehiclePreset.sedan.rawValue
        let preset = VehiclePreset(rawValue: presetRaw) ?? .sedan
        selectedPresetPublisher.send(preset)

        if let filename = defaults.string(forKey: customImageKey),
           FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent(filename).path) {
            iconSourcePublisher.send(.custom(filename))
            return
        }

        if let filename = defaults.string(forKey: model3DKey),
           FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent(filename).path) {
            iconSourcePublisher.send(.model3D(filename))
            return
        }

        iconSourcePublisher.send(.preset(preset))
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func grayscale() -> UIImage {
        let context = CIContext()
        guard let ciImage = CIImage(image: self),
              let filter = CIFilter(name: "CIPhotoEffectMono") else { return self }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}
