import Foundation
import Combine

final class DevToolsViewModel {

    // MARK: - Keys

    private enum Keys {
        static let debugOverlayEnabled = "devtools_debug_overlay_enabled"
    }

    // MARK: - Publishers

    let recordingState = CurrentValueSubject<GPXRecorder.RecordingState, Never>(.idle)
    let recordingDuration = CurrentValueSubject<TimeInterval, Never>(0)
    let recordingPointCount = CurrentValueSubject<Int, Never>(0)
    let recordingDistance = CurrentValueSubject<Double, Never>(0)
    let gpxFileCount = CurrentValueSubject<Int, Never>(0)
    let debugOverlayEnabled = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Dependencies

    private let recorder: GPXRecorder
    private let dataService: DataService
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(recorder: GPXRecorder = .shared, dataService: DataService = .shared) {
        self.recorder = recorder
        self.dataService = dataService
        loadSettings()
        bindRecorder()
    }

    // MARK: - Settings

    private func loadSettings() {
        debugOverlayEnabled.send(defaults.bool(forKey: Keys.debugOverlayEnabled))
        gpxFileCount.send(dataService.fetchGPXRecords().count)
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

    // MARK: - Actions

    func toggleRecording() {
        switch recorder.statePublisher.value {
        case .idle:
            recorder.startRecording()
        case .recording:
            stopAndSave()
        case .paused:
            recorder.resumeRecording()
        }
    }

    func pauseRecording() {
        recorder.pauseRecording()
    }

    func setDebugOverlayEnabled(_ enabled: Bool) {
        debugOverlayEnabled.send(enabled)
        defaults.set(enabled, forKey: Keys.debugOverlayEnabled)
    }

    func refreshFileCount() {
        gpxFileCount.send(dataService.fetchGPXRecords().count)
    }

    // MARK: - Private

    private func stopAndSave() {
        guard let result = recorder.stopRecording() else { return }

        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(
            atPath: result.fileURL.path
        )[.size] as? Int64) ?? 0

        dataService.saveGPXRecord(
            fileName: result.fileURL.lastPathComponent,
            filePath: "GPXRecordings/\(result.fileURL.lastPathComponent)",
            duration: result.duration,
            distance: result.distance,
            pointCount: result.pointCount,
            fileSize: fileSize
        )

        refreshFileCount()
    }
}
