import Foundation
import Combine

final class DevToolsViewModel {

    // MARK: - Keys

    private enum Keys {
        static let debugOverlayEnabled = "devtools_debug_overlay_enabled"
    }

    // MARK: - Publishers

    let recordingState = CurrentValueSubject<LocationRecorder.RecordingState, Never>(.idle)
    let recordingDuration = CurrentValueSubject<TimeInterval, Never>(0)
    let recordingPointCount = CurrentValueSubject<Int, Never>(0)
    let recordingDistance = CurrentValueSubject<Double, Never>(0)
    let gpxFileCount = CurrentValueSubject<Int, Never>(0)
    let debugOverlayEnabled = CurrentValueSubject<Bool, Never>(false)
    let locationType = CurrentValueSubject<DevToolsSettings.LocationType, Never>(.real)
    let selectedRecordingFileName = CurrentValueSubject<String?, Never>(nil)

    // MARK: - Dependencies

    private let recorder: LocationRecorder
    private let dataService: DataService
    private let settings: DevToolsSettings
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(
        recorder: LocationRecorder = .shared,
        dataService: DataService = .shared,
        settings: DevToolsSettings = .shared
    ) {
        self.recorder = recorder
        self.dataService = dataService
        self.settings = settings
        loadSettings()
        bindRecorder()
        bindSettings()
    }

    // MARK: - Settings

    private func loadSettings() {
        debugOverlayEnabled.send(defaults.bool(forKey: Keys.debugOverlayEnabled))
        gpxFileCount.send(dataService.fetchRecordings().count)
    }

    private func bindRecorder() {
        recorder.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.recordingState.send(state)
            }
            .store(in: &cancellables)

        recorder.durationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                self?.recordingDuration.send(duration)
            }
            .store(in: &cancellables)

        recorder.pointCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.recordingPointCount.send(count)
            }
            .store(in: &cancellables)

        recorder.distancePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] distance in
                self?.recordingDistance.send(distance)
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        settings.locationType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] type in
                self?.locationType.send(type)
            }
            .store(in: &cancellables)

        settings.selectedRecordingFileName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.selectedRecordingFileName.send(name)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// 1회 자동 녹화 토글 (idle ↔ armed)
    /// 주행 시작/종료 시 AppCoordinator가 자동으로 녹화를 시작/종료함
    func toggleRecording() {
        let state = recorder.statePublisher.value
        print("[GPX-DEBUG] toggleRecording() — current=\(state)")
        switch state {
        case .idle:
            recorder.arm()                  // 다음 주행 시 자동 녹화
        case .armed:
            recorder.disarm()               // 자동 녹화 OFF
        case .recording, .paused:
            // 주행 중이면 사용자가 직접 정지할 수 있음 (옵션)
            stopAndSave()
        }
    }

    func setDebugOverlayEnabled(_ enabled: Bool) {
        debugOverlayEnabled.send(enabled)
        defaults.set(enabled, forKey: Keys.debugOverlayEnabled)
    }

    func setLocationType(_ type: DevToolsSettings.LocationType) {
        settings.setLocationType(type)
    }

    func setSelectedRecordingFileName(_ name: String?) {
        settings.setSelectedRecordingFileName(name)
    }

    func refreshFileCount() {
        gpxFileCount.send(dataService.fetchRecordings().count)
    }

    // MARK: - Private

    private func stopAndSave() {
        guard let result = recorder.stopRecording() else { return }

        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(
            atPath: result.fileURL.path
        )[.size] as? Int64) ?? 0

        dataService.saveRecording(
            fileName: result.fileURL.lastPathComponent,
            filePath: "Recordings/\(result.fileURL.lastPathComponent)",
            duration: result.duration,
            distance: result.distance,
            pointCount: result.pointCount,
            fileSize: fileSize,
            recordingMode: result.recordingMode.rawValue,
            originName: result.originName,
            destinationName: result.destinationName
        )

        refreshFileCount()
    }
}
