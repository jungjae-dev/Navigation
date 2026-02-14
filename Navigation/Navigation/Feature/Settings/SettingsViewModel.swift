import Foundation
import Combine
import MapKit

final class SettingsViewModel {

    // MARK: - Settings Keys

    private enum Keys {
        static let voiceEnabled = "settings_voice_enabled"
        static let voiceSpeed = "settings_voice_speed"
        static let mapType = "settings_map_type"
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
