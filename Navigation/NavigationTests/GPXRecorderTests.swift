import Testing
import Combine
import CoreLocation
@testable import Navigation

struct GPXRecorderTests {

    // MARK: - Helpers

    private func makeLocationPublisher() -> (CurrentValueSubject<CLLocation?, Never>, GPXRecorder) {
        let subject = CurrentValueSubject<CLLocation?, Never>(nil)
        let recorder = GPXRecorder(locationPublisher: subject.eraseToAnyPublisher())
        return (subject, recorder)
    }

    private func makeLocation(lat: Double = 37.5665, lon: Double = 126.978) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 30,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
    }

    // MARK: - State Transition Tests

    @Test func initialStateIsIdle() {
        let (_, recorder) = makeLocationPublisher()
        #expect(recorder.statePublisher.value == .idle)
        #expect(recorder.durationPublisher.value == 0)
        #expect(recorder.pointCountPublisher.value == 0)
    }

    @Test func startRecordingChangesState() {
        let (_, recorder) = makeLocationPublisher()
        recorder.startRecording()
        #expect(recorder.statePublisher.value == .recording)
    }

    @Test func pauseRecordingChangesState() {
        let (_, recorder) = makeLocationPublisher()
        recorder.startRecording()
        recorder.pauseRecording()
        #expect(recorder.statePublisher.value == .paused)
    }

    @Test func resumeRecordingChangesState() {
        let (_, recorder) = makeLocationPublisher()
        recorder.startRecording()
        recorder.pauseRecording()
        recorder.resumeRecording()
        #expect(recorder.statePublisher.value == .recording)
    }

    @Test func stopRecordingReturnsToIdle() {
        let (_, recorder) = makeLocationPublisher()
        recorder.startRecording()
        _ = recorder.stopRecording()
        #expect(recorder.statePublisher.value == .idle)
    }

    @Test func stopIdleReturnsNil() {
        let (_, recorder) = makeLocationPublisher()
        let result = recorder.stopRecording()
        #expect(result == nil)
    }

    @Test func startWhileRecordingDoesNothing() {
        let (_, recorder) = makeLocationPublisher()
        recorder.startRecording()
        recorder.startRecording()
        #expect(recorder.statePublisher.value == .recording)
    }

    // MARK: - Location Collection Tests

    @Test func locationUpdatesIncrementPointCount() {
        let (subject, recorder) = makeLocationPublisher()
        recorder.startRecording()

        subject.send(makeLocation(lat: 37.5665, lon: 126.978))
        subject.send(makeLocation(lat: 37.5675, lon: 126.979))
        subject.send(makeLocation(lat: 37.5685, lon: 126.980))

        #expect(recorder.pointCountPublisher.value == 3)
    }

    @Test func distanceAccumulatesWithLocations() {
        let (subject, recorder) = makeLocationPublisher()
        recorder.startRecording()

        subject.send(makeLocation(lat: 37.5665, lon: 126.978))
        subject.send(makeLocation(lat: 37.5675, lon: 126.978))

        // Approximately 111m per 0.001 degree of latitude
        #expect(recorder.distancePublisher.value > 50)
    }

    @Test func pausedRecorderDoesNotCollectLocations() {
        let (subject, recorder) = makeLocationPublisher()
        recorder.startRecording()

        subject.send(makeLocation(lat: 37.5665, lon: 126.978))
        #expect(recorder.pointCountPublisher.value == 1)

        recorder.pauseRecording()
        subject.send(makeLocation(lat: 37.5675, lon: 126.979))

        // Should still be 1 since paused
        #expect(recorder.pointCountPublisher.value == 1)
    }

    // MARK: - GPX Generation Tests

    @Test func generateGPXStringContainsValidXML() {
        let (subject, recorder) = makeLocationPublisher()
        recorder.startRecording()

        subject.send(makeLocation(lat: 37.5665, lon: 126.978))
        subject.send(makeLocation(lat: 37.5675, lon: 126.979))

        let gpx = recorder.generateGPXString()

        #expect(gpx.contains("<?xml"))
        #expect(gpx.contains("<gpx"))
        #expect(gpx.contains("<trk>"))
        #expect(gpx.contains("<trkpt"))
        #expect(gpx.contains("37.5665"))
        #expect(gpx.contains("126.978"))
        #expect(gpx.contains("</gpx>"))

        _ = recorder.stopRecording()
    }

    // MARK: - File Save Tests

    @Test func stopRecordingSavesFile() {
        let (subject, recorder) = makeLocationPublisher()
        recorder.startRecording()

        subject.send(makeLocation(lat: 37.5665, lon: 126.978))
        subject.send(makeLocation(lat: 37.5675, lon: 126.979))

        let result = recorder.stopRecording()

        #expect(result != nil)
        #expect(result!.pointCount == 2)
        #expect(result!.distance > 0)
        #expect(result!.fileURL.pathExtension == "gpx")
        #expect(FileManager.default.fileExists(atPath: result!.fileURL.path))

        // Cleanup
        try? FileManager.default.removeItem(at: result!.fileURL)
    }

    @Test func stopRecordingWithNoLocationsReturnsNil() {
        let (_, recorder) = makeLocationPublisher()
        recorder.startRecording()

        let result = recorder.stopRecording()
        #expect(result == nil)
    }

    @Test func gpxDocumentsDirectoryPath() {
        let (_, recorder) = makeLocationPublisher()
        let dir = recorder.gpxDocumentsDirectory()
        #expect(dir.lastPathComponent == "GPXRecordings")
    }
}
