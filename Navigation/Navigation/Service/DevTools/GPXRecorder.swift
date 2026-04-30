import Foundation
import CoreLocation
import Combine

final class GPXRecorder {

    // MARK: - Types

    enum RecordingState: Equatable {
        case idle           // 녹화 안 함
        case armed          // ON 대기 (다음 주행 시 자동 녹화)
        case recording      // 녹화 중
        case paused
    }

    enum RecordingMode: String {
        case real           // 실제 GPS
        case simul          // 가상 주행
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

    // 현재 녹화 메타데이터
    private var currentMode: RecordingMode = .real
    private var currentOriginName: String?
    private var currentDestinationName: String?

    // MARK: - Init

    init(locationPublisher: AnyPublisher<CLLocation?, Never> = LocationService.shared.locationPublisher.eraseToAnyPublisher()) {
        self.locationSource = locationPublisher
    }

    private convenience init() {
        self.init(locationPublisher: LocationService.shared.locationPublisher.eraseToAnyPublisher())
    }

    // MARK: - Public Methods

    /// 1회 자동 녹화 ON (다음 주행 시작 시 자동으로 녹화 시작)
    func arm() {
        guard statePublisher.value == .idle else {
            print("[GPX-DEBUG] arm() skipped — state=\(statePublisher.value)")
            return
        }
        print("[GPX-DEBUG] arm() → armed")
        statePublisher.send(.armed)
    }

    /// 자동 녹화 OFF
    func disarm() {
        guard statePublisher.value == .armed else {
            print("[GPX-DEBUG] disarm() skipped — state=\(statePublisher.value)")
            return
        }
        print("[GPX-DEBUG] disarm() → idle")
        statePublisher.send(.idle)
    }

    /// 녹화가 ON 대기 중인지
    var isArmed: Bool { statePublisher.value == .armed }

    /// 주행 시작 시 호출 — armed 상태면 자동으로 녹화 시작
    /// - Returns: 실제로 녹화가 시작되었는지
    @discardableResult
    func startRecordingIfArmed(
        mode: RecordingMode,
        originName: String? = nil,
        destinationName: String? = nil
    ) -> Bool {
        guard statePublisher.value == .armed else { return false }
        startRecording(mode: mode, originName: originName, destinationName: destinationName)
        return true
    }

    /// 녹화 직접 시작 (메타데이터 포함)
    func startRecording(
        mode: RecordingMode = .real,
        originName: String? = nil,
        destinationName: String? = nil
    ) {
        guard statePublisher.value == .idle || statePublisher.value == .armed else {
            print("[GPX-DEBUG] startRecording() skipped — state=\(statePublisher.value)")
            return
        }
        print("[GPX-DEBUG] startRecording() mode=\(mode.rawValue) origin=\(originName ?? "nil") dest=\(destinationName ?? "nil")")

        recordedLocations = []
        totalDistance = 0
        pausedDuration = 0
        pauseStart = nil
        startDate = Date()
        currentMode = mode
        currentOriginName = originName
        currentDestinationName = destinationName

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
        guard statePublisher.value == .recording || statePublisher.value == .paused else {
            print("[GPX-DEBUG] stopRecording() skipped — state=\(statePublisher.value)")
            return nil
        }
        print("[GPX-DEBUG] stopRecording() — points=\(recordedLocations.count) distance=\(Int(totalDistance))m")

        locationCancellable?.cancel()
        locationCancellable = nil
        durationTimer?.invalidate()
        durationTimer = nil

        let duration = durationPublisher.value
        let fileURL = saveToFile()
        print("[GPX-DEBUG] stopRecording() — fileURL=\(fileURL?.lastPathComponent ?? "nil")")

        let result: RecordingResult? = fileURL.map {
            RecordingResult(
                fileURL: $0,
                duration: duration,
                distance: totalDistance,
                pointCount: recordedLocations.count,
                startDate: startDate ?? Date(),
                recordingMode: currentMode,
                originName: currentOriginName,
                destinationName: currentDestinationName
            )
        }

        // Reset state (자동 OFF)
        statePublisher.send(.idle)
        durationPublisher.send(0)
        pointCountPublisher.send(0)
        distancePublisher.send(0)
        currentOriginName = nil
        currentDestinationName = nil

        return result
    }

    // MARK: - Internal (for testing)

    func gpxDocumentsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("GPXRecordings")
    }

    // MARK: - Private

    private func subscribeToLocation() {
        print("[GPX-DEBUG] subscribeToLocation()")
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
        let count = recordedLocations.count
        if count == 1 || count % 20 == 0 {
            print("[GPX-DEBUG] appendLocation() count=\(count) lat=\(location.coordinate.latitude) lon=\(location.coordinate.longitude)")
        }
    }

    private func saveToFile() -> URL? {
        guard !recordedLocations.isEmpty else {
            print("[GPX-DEBUG] saveToFile() skipped — no locations recorded")
            return nil
        }

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
            print("[GPX-DEBUG] saveToFile() OK → \(fileURL.path)")
            return fileURL
        } catch {
            print("[GPX-DEBUG] saveToFile() FAILED — \(error)")
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
        let timestamp = formatter.string(from: Date())

        let mode = currentMode.rawValue
        let origin = sanitizeForFilename(currentOriginName) ?? "출발"
        let destination = sanitizeForFilename(currentDestinationName) ?? "도착"

        return "\(mode)_\(origin)_\(destination)_\(timestamp).gpx"
    }

    /// 파일명에 사용 불가능한 문자 제거 (공백, /, \, :, *, ?, ", <, >, |)
    private func sanitizeForFilename(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let invalidChars: Set<Character> = [" ", "/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        let sanitized = String(name.filter { !invalidChars.contains($0) })
        return sanitized.isEmpty ? nil : sanitized
    }
}
