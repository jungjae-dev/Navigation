import Foundation
import CoreLocation
import Combine

/// GPS 위치를 NDJSON 파일에 스트리밍 기록.
/// 위치를 메모리에 쌓지 않고 즉시 파일에 append 하므로 장시간 녹화 가능.
/// GPXRecorder 와 동일한 public API.
final class LocationRecorder {

    // MARK: - Types

    enum RecordingState: Equatable {
        case idle
        case armed
        case recording
        case paused
    }

    enum RecordingMode: String {
        case real
        case simul
    }

    struct RecordingResult {
        let fileURL: URL
        let duration: TimeInterval
        let distance: CLLocationDistance
        let pointCount: Int
        let startDate: Date
        let recordingMode: RecordingMode
        let originName: String?
        let destinationName: String?
    }

    // MARK: - Singleton

    static let shared = LocationRecorder()

    // MARK: - Publishers

    let statePublisher = CurrentValueSubject<RecordingState, Never>(.idle)
    let durationPublisher = CurrentValueSubject<TimeInterval, Never>(0)
    let pointCountPublisher = CurrentValueSubject<Int, Never>(0)
    let distancePublisher = CurrentValueSubject<CLLocationDistance, Never>(0)

    // MARK: - Private

    private var fileWriter: LocationFileWriter?
    private var pointCount: Int = 0
    private var lastLocation: CLLocation?
    private var startDate: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStart: Date?
    private var totalDistance: CLLocationDistance = 0
    private var durationTimer: Timer?
    private var locationCancellable: AnyCancellable?
    private var currentLocationSource: AnyPublisher<CLLocation, Never>

    private var currentMode: RecordingMode = .real
    private var currentOriginName: String?
    private var currentDestinationName: String?

    // MARK: - Init

    private init() {
        self.currentLocationSource = LocationService.shared.locationPublisher
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    // MARK: - Public

    func arm() {
        guard statePublisher.value == .idle else { return }
        statePublisher.send(.armed)
    }

    func disarm() {
        guard statePublisher.value == .armed else { return }
        statePublisher.send(.idle)
    }

    var isArmed: Bool { statePublisher.value == .armed }

    @discardableResult
    func startRecordingIfArmed(
        mode: RecordingMode,
        originName: String? = nil,
        destinationName: String? = nil,
        locationSource: AnyPublisher<CLLocation, Never>? = nil
    ) -> Bool {
        guard statePublisher.value == .armed else { return false }
        startRecording(mode: mode, originName: originName, destinationName: destinationName, locationSource: locationSource)
        return true
    }

    func startRecording(
        mode: RecordingMode = .real,
        originName: String? = nil,
        destinationName: String? = nil,
        locationSource: AnyPublisher<CLLocation, Never>? = nil
    ) {
        guard statePublisher.value == .idle || statePublisher.value == .armed else { return }

        pointCount = 0
        lastLocation = nil
        totalDistance = 0
        pausedDuration = 0
        pauseStart = nil
        startDate = Date()
        currentMode = mode
        currentOriginName = originName
        currentDestinationName = destinationName
        currentLocationSource = locationSource ?? LocationService.shared.locationPublisher
            .compactMap { $0 }
            .eraseToAnyPublisher()

        // 파일 생성 — 실패 시 녹화 진행 불가
        let fileURL = makeFileURL(mode: mode)
        guard let writer = try? LocationFileWriter(fileURL: fileURL) else {
            print("[LocationRecorder] 파일 생성 실패: \(fileURL.lastPathComponent)")
            statePublisher.send(.idle)
            return
        }
        fileWriter = writer

        statePublisher.send(.recording)
        durationPublisher.send(0)
        pointCountPublisher.send(0)
        distancePublisher.send(0)

        subscribeToLocation()
        startDurationTimer()
    }

    func pauseRecording() {
        guard statePublisher.value == .recording else { return }
        statePublisher.send(.paused)
        pauseStart = Date()
        locationCancellable?.cancel()
        locationCancellable = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func resumeRecording() {
        guard statePublisher.value == .paused else { return }
        if let pauseStart { pausedDuration += Date().timeIntervalSince(pauseStart) }
        pauseStart = nil
        statePublisher.send(.recording)
        subscribeToLocation()
        startDurationTimer()
    }

    @discardableResult
    func stopRecording() -> RecordingResult? {
        guard statePublisher.value == .recording || statePublisher.value == .paused else { return nil }

        locationCancellable?.cancel()
        locationCancellable = nil
        durationTimer?.invalidate()
        durationTimer = nil

        let duration = durationPublisher.value
        fileWriter?.close()
        let fileURL = fileWriter?.fileURL

        let result: RecordingResult? = fileURL.map { url in
            RecordingResult(
                fileURL: url,
                duration: duration,
                distance: totalDistance,
                pointCount: pointCount,
                startDate: startDate ?? Date(),
                recordingMode: currentMode,
                originName: currentOriginName,
                destinationName: currentDestinationName
            )
        }

        fileWriter = nil
        statePublisher.send(.idle)
        durationPublisher.send(0)
        pointCountPublisher.send(0)
        distancePublisher.send(0)
        currentOriginName = nil
        currentDestinationName = nil

        return result
    }

    // MARK: - Directory (for testing)

    func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Recordings")
    }

    // MARK: - Private

    private func subscribeToLocation() {
        locationCancellable = currentLocationSource
            .sink { [weak self] location in
                self?.appendLocation(location)
            }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            let elapsed = Date().timeIntervalSince(start) - self.pausedDuration
            self.durationPublisher.send(max(0, elapsed))
        }
    }

    private func appendLocation(_ location: CLLocation) {
        if let last = lastLocation {
            totalDistance += location.distance(from: last)
            distancePublisher.send(totalDistance)
        }
        lastLocation = location
        if (try? fileWriter?.write(location)) != nil {
            pointCount += 1
            pointCountPublisher.send(pointCount)
        }
    }

    private func makeFileURL(mode: RecordingMode) -> URL {
        let directory = recordingsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let prefix = mode == .simul ? "simul" : "real"
        let fileName = "\(prefix)_\(timestamp).ndjson"
        return directory.appendingPathComponent(fileName)
    }
}
