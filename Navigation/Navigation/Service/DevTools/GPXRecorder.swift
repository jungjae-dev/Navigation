import Foundation
import CoreLocation
import Combine

final class GPXRecorder {

    // MARK: - Types

    enum RecordingState: Equatable {
        case idle
        case recording
        case paused
    }

    struct RecordingResult {
        let fileURL: URL
        let duration: TimeInterval
        let distance: CLLocationDistance
        let pointCount: Int
        let startDate: Date
    }

    // MARK: - Singleton

    static let shared = GPXRecorder()

    // MARK: - Publishers

    let statePublisher = CurrentValueSubject<RecordingState, Never>(.idle)
    let durationPublisher = CurrentValueSubject<TimeInterval, Never>(0)
    let pointCountPublisher = CurrentValueSubject<Int, Never>(0)
    let distancePublisher = CurrentValueSubject<CLLocationDistance, Never>(0)

    // MARK: - Private

    private var recordedLocations: [CLLocation] = []
    private var startDate: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStart: Date?
    private var totalDistance: CLLocationDistance = 0
    private var durationTimer: Timer?
    private var locationCancellable: AnyCancellable?
    private let locationSource: AnyPublisher<CLLocation?, Never>

    // MARK: - Init

    init(locationPublisher: AnyPublisher<CLLocation?, Never> = LocationService.shared.locationPublisher.eraseToAnyPublisher()) {
        self.locationSource = locationPublisher
    }

    private convenience init() {
        self.init(locationPublisher: LocationService.shared.locationPublisher.eraseToAnyPublisher())
    }

    // MARK: - Public Methods

    func startRecording() {
        guard statePublisher.value == .idle else { return }

        recordedLocations = []
        totalDistance = 0
        pausedDuration = 0
        pauseStart = nil
        startDate = Date()

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

        if let pauseStart {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }
        pauseStart = nil

        statePublisher.send(.recording)
        subscribeToLocation()
        startDurationTimer()
    }

    @discardableResult
    func stopRecording() -> RecordingResult? {
        guard statePublisher.value != .idle else { return nil }

        locationCancellable?.cancel()
        locationCancellable = nil
        durationTimer?.invalidate()
        durationTimer = nil

        let duration = durationPublisher.value
        let fileURL = saveToFile()

        let result: RecordingResult? = fileURL.map {
            RecordingResult(
                fileURL: $0,
                duration: duration,
                distance: totalDistance,
                pointCount: recordedLocations.count,
                startDate: startDate ?? Date()
            )
        }

        // Reset state
        statePublisher.send(.idle)
        durationPublisher.send(0)
        pointCountPublisher.send(0)
        distancePublisher.send(0)

        return result
    }

    // MARK: - Internal (for testing)

    func gpxDocumentsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("GPXRecordings")
    }

    // MARK: - Private

    private func subscribeToLocation() {
        locationCancellable = locationSource
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.appendLocation(location)
            }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            let elapsed = Date().timeIntervalSince(start) - self.pausedDuration
            self.durationPublisher.send(max(0, elapsed))
        }
    }

    private func appendLocation(_ location: CLLocation) {
        if let last = recordedLocations.last {
            totalDistance += location.distance(from: last)
            distancePublisher.send(totalDistance)
        }
        recordedLocations.append(location)
        pointCountPublisher.send(recordedLocations.count)
    }

    private func saveToFile() -> URL? {
        guard !recordedLocations.isEmpty else { return nil }

        let gpxString = generateGPXString()
        let fileName = generateFileName()
        let directory = gpxDocumentsDirectory()

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileURL = directory.appendingPathComponent(fileName)

        do {
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("[GPXRecorder] Save failed: \(error)")
            return nil
        }
    }

    func generateGPXString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="NavigationApp"
             xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Recorded Track</name>
            <trkseg>

        """

        for location in recordedLocations {
            xml += "      <trkpt lat=\"\(location.coordinate.latitude)\" lon=\"\(location.coordinate.longitude)\">\n"
            xml += "        <ele>\(location.altitude)</ele>\n"
            xml += "        <time>\(formatter.string(from: location.timestamp))</time>\n"
            xml += "      </trkpt>\n"
        }

        xml += """
            </trkseg>
          </trk>
        </gpx>

        """

        return xml
    }

    private func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "track_\(formatter.string(from: Date())).gpx"
    }
}
