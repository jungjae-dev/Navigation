import Foundation
import Combine
import MapKit

final class SettingsViewModel {

    // MARK: - Settings Keys

    private enum Keys {
        static let voiceEnabled = "settings_voice_enabled"
        static let voiceSpeed = "settings_voice_speed"
        static let mapType = "settings_map_type"
        static let defaultTransportMode = "settings_default_transport_mode"
        static let hapticEnabled = "settings_haptic_enabled"
        static let vehiclePreset = "settings_vehicle_preset"
        static let vehicle3DEnabled = "settings_vehicle_3d_enabled"
    }

    // MARK: - Voice Speed

    enum VoiceSpeed: Int, CaseIterable {
        case slow = 0
        case normal = 1
        case fast = 2

        var displayName: String {
            switch self {
            case .slow: return "느리게"
            case .normal: return "보통"
            case .fast: return "빠르게"
            }
        }

        var rate: Float {
            switch self {
            case .slow: return 0.40
            case .normal: return 0.50
            case .fast: return 0.60
            }
        }
    }

    // MARK: - Map Type

    enum MapTypeOption: Int, CaseIterable {
        case standard = 0
        case satellite = 1
        case hybrid = 2

        var displayName: String {
            switch self {
            case .standard: return "일반"
            case .satellite: return "위성"
            case .hybrid: return "하이브리드"
            }
        }

        var mkMapType: MKMapType {
            switch self {
            case .standard: return .standard
            case .satellite: return .satellite
            case .hybrid: return .hybrid
            }
        }
    }

    // MARK: - Publishers

    let voiceEnabled = CurrentValueSubject<Bool, Never>(true)
    let voiceSpeed = CurrentValueSubject<VoiceSpeed, Never>(.normal)
    let mapType = CurrentValueSubject<MapTypeOption, Never>(.standard)
    let defaultTransportMode = CurrentValueSubject<TransportMode, Never>(.automobile)
    let hapticEnabled = CurrentValueSubject<Bool, Never>(true)
    let vehiclePreset = CurrentValueSubject<VehiclePreset, Never>(.sedan)
    let vehicle3DEnabled = CurrentValueSubject<Bool, Never>(false)
    let favoriteCount = CurrentValueSubject<Int, Never>(0)
    let searchHistoryCount = CurrentValueSubject<Int, Never>(0)

    // MARK: - Private

    private let defaults = UserDefaults.standard
    private let dataService: DataService

    // MARK: - Init

    init(dataService: DataService = .shared) {
        self.dataService = dataService
        loadSettings()
    }

    // MARK: - Settings Load/Save

    private func loadSettings() {
        // Voice enabled (default: true)
        if defaults.object(forKey: Keys.voiceEnabled) != nil {
            voiceEnabled.send(defaults.bool(forKey: Keys.voiceEnabled))
        } else {
            voiceEnabled.send(true)
        }

        // Voice speed (default: normal)
        let speedRaw = defaults.integer(forKey: Keys.voiceSpeed)
        voiceSpeed.send(VoiceSpeed(rawValue: speedRaw) ?? .normal)

        // Map type (default: standard)
        let mapRaw = defaults.integer(forKey: Keys.mapType)
        mapType.send(MapTypeOption(rawValue: mapRaw) ?? .standard)

        // Default transport mode
        if let modeRaw = defaults.string(forKey: Keys.defaultTransportMode) {
            defaultTransportMode.send(TransportMode(rawValue: modeRaw) ?? .automobile)
        }

        // Haptic enabled (default: true)
        if defaults.object(forKey: Keys.hapticEnabled) != nil {
            hapticEnabled.send(defaults.bool(forKey: Keys.hapticEnabled))
        } else {
            hapticEnabled.send(true)
        }

        // Vehicle preset
        if let presetRaw = defaults.string(forKey: Keys.vehiclePreset) {
            vehiclePreset.send(VehiclePreset(rawValue: presetRaw) ?? .sedan)
        }

        // Vehicle 3D enabled (default: false)
        vehicle3DEnabled.send(defaults.bool(forKey: Keys.vehicle3DEnabled))

        // Data counts
        favoriteCount.send(dataService.fetchFavorites().count)
        searchHistoryCount.send(dataService.fetchRecentSearches(limit: 1000).count)
    }

    // MARK: - Actions

    func setVoiceEnabled(_ enabled: Bool) {
        voiceEnabled.send(enabled)
        defaults.set(enabled, forKey: Keys.voiceEnabled)
    }

    func setVoiceSpeed(_ speed: VoiceSpeed) {
        voiceSpeed.send(speed)
        defaults.set(speed.rawValue, forKey: Keys.voiceSpeed)
    }

    func setMapType(_ type: MapTypeOption) {
        mapType.send(type)
        defaults.set(type.rawValue, forKey: Keys.mapType)
    }

    func setDefaultTransportMode(_ mode: TransportMode) {
        defaultTransportMode.send(mode)
        defaults.set(mode.rawValue, forKey: Keys.defaultTransportMode)
    }

    func setHapticEnabled(_ enabled: Bool) {
        hapticEnabled.send(enabled)
        defaults.set(enabled, forKey: Keys.hapticEnabled)
        HapticService.shared.setEnabled(enabled)
    }

    func setVehiclePreset(_ preset: VehiclePreset) {
        vehiclePreset.send(preset)
        defaults.set(preset.rawValue, forKey: Keys.vehiclePreset)
        VehicleIconService.shared.selectPreset(preset)
    }

    func setVehicle3DEnabled(_ enabled: Bool) {
        vehicle3DEnabled.send(enabled)
        defaults.set(enabled, forKey: Keys.vehicle3DEnabled)
    }

    func clearSearchHistory() {
        dataService.clearAllSearchHistory()
        searchHistoryCount.send(0)
    }

    func refreshDataCounts() {
        favoriteCount.send(dataService.fetchFavorites().count)
        searchHistoryCount.send(dataService.fetchRecentSearches(limit: 1000).count)
    }

    // MARK: - App Info

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}
