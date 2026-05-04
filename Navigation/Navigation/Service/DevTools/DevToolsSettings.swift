import Foundation
import Combine

/// 개발자 도구 설정 (앱 전역 공유)
/// AppCoordinator + DevToolsViewModel 양쪽에서 참조
final class DevToolsSettings {

    enum LocationType: String {
        case real
        case file
    }

    static let shared = DevToolsSettings()

    // MARK: - Keys

    private enum Keys {
        static let locationType = "devtools_location_type"
        static let selectedRecordingPath = "devtools_selected_recording_path"
        static let mapMatchDebugEnabled = "devtools_mapmatch_debug_enabled"
    }

    // MARK: - Publishers

    let locationType: CurrentValueSubject<LocationType, Never>
    let selectedRecordingFileName: CurrentValueSubject<String?, Never>
    let mapMatchDebugEnabled: CurrentValueSubject<Bool, Never>

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private init() {
        let rawType = defaults.string(forKey: Keys.locationType) ?? LocationType.real.rawValue
        let initialType = LocationType(rawValue: rawType) ?? .real
        self.locationType = CurrentValueSubject(initialType)
        self.selectedRecordingFileName = CurrentValueSubject(defaults.string(forKey: Keys.selectedRecordingPath))
        self.mapMatchDebugEnabled = CurrentValueSubject(defaults.bool(forKey: Keys.mapMatchDebugEnabled))
    }

    // MARK: - Setters

    func setLocationType(_ type: LocationType) {
        locationType.send(type)
        defaults.set(type.rawValue, forKey: Keys.locationType)
    }

    func setMapMatchDebugEnabled(_ enabled: Bool) {
        mapMatchDebugEnabled.send(enabled)
        defaults.set(enabled, forKey: Keys.mapMatchDebugEnabled)
    }

    func setSelectedRecordingFileName(_ fileName: String?) {
        selectedRecordingFileName.send(fileName)
        if let fileName {
            defaults.set(fileName, forKey: Keys.selectedRecordingPath)
        } else {
            defaults.removeObject(forKey: Keys.selectedRecordingPath)
        }
    }

    // MARK: - Resolved File URL

    var selectedRecordingFileURL: URL? {
        guard let fileName = selectedRecordingFileName.value else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Recordings").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func validateSelection() {
        let fileName = selectedRecordingFileName.value
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let fileExists: Bool
        if let fileName {
            let url = docs.appendingPathComponent("Recordings").appendingPathComponent(fileName)
            fileExists = FileManager.default.fileExists(atPath: url.path)
        } else {
            fileExists = false
        }

        if !fileExists {
            if fileName != nil { setSelectedRecordingFileName(nil) }
            if locationType.value == .file { setLocationType(.real) }
        }
    }
}
