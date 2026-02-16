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
    case custom(String) // filename in documents directory

    var isCustom: Bool {
        if case .custom = self { return true }
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
            let url = documentsDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
        defaults.removeObject(forKey: customImageKey)
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
        }
    }

    // MARK: - Private

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func loadSettings() {
        // Check for custom image first
        if let filename = defaults.string(forKey: customImageKey) {
            let url = documentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let presetRaw = defaults.string(forKey: presetKey) ?? VehiclePreset.sedan.rawValue
                let preset = VehiclePreset(rawValue: presetRaw) ?? .sedan
                selectedPresetPublisher.send(preset)
                iconSourcePublisher.send(.custom(filename))
                return
            }
        }

        // Load preset
        let presetRaw = defaults.string(forKey: presetKey) ?? VehiclePreset.sedan.rawValue
        let preset = VehiclePreset(rawValue: presetRaw) ?? .sedan
        selectedPresetPublisher.send(preset)
        iconSourcePublisher.send(.preset(preset))
    }
}

// MARK: - UIImage Resize Extension

private extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
