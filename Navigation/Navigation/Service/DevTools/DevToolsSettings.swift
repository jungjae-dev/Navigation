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
        static let selectedGPXPath = "devtools_selected_gpx_path"
    }

    // MARK: - Publishers

    let locationType: CurrentValueSubject<LocationType, Never>
    let selectedGPXFileName: CurrentValueSubject<String?, Never>

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private init() {
        let rawType = defaults.string(forKey: Keys.locationType) ?? LocationType.real.rawValue
        let initialType = LocationType(rawValue: rawType) ?? .real
        self.locationType = CurrentValueSubject(initialType)
        self.selectedGPXFileName = CurrentValueSubject(defaults.string(forKey: Keys.selectedGPXPath))
    }

    // MARK: - Setters

    func setLocationType(_ type: LocationType) {
        locationType.send(type)
        defaults.set(type.rawValue, forKey: Keys.locationType)
    }

    /// 선택된 GPX 파일명 (Documents/GPXRecordings/ 기준)
    func setSelectedGPXFileName(_ fileName: String?) {
        selectedGPXFileName.send(fileName)
        if let fileName {
            defaults.set(fileName, forKey: Keys.selectedGPXPath)
        } else {
            defaults.removeObject(forKey: Keys.selectedGPXPath)
        }
    }

    // MARK: - Resolved File URL

    /// 선택된 GPX 파일의 절대 URL (없으면 nil)
    var selectedGPXFileURL: URL? {
        guard let fileName = selectedGPXFileName.value else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("GPXRecordings").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 선택된 파일이 디스크에 없으면 nil로 리셋
    /// - 호출 시점: 파일 삭제 후 / DevTools 진입 시
    func validateSelection() {
        guard let fileName = selectedGPXFileName.value else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("GPXRecordings").appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            setSelectedGPXFileName(nil)
        }
    }
}
