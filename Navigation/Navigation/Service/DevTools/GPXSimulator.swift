import Foundation
import CoreLocation
import Combine

final class GPXSimulator {

    // MARK: - Publishers

    let simulatedLocationPublisher = PassthroughSubject<CLLocation, Never>()
    let isPlayingPublisher = CurrentValueSubject<Bool, Never>(false)
    let progressPublisher = CurrentValueSubject<Double, Never>(0.0)
    let speedMultiplierPublisher = CurrentValueSubject<Double, Never>(1.0)

    // MARK: - Configuration

    var speedMultiplier: Double = 1.0 {
        didSet { speedMultiplierPublisher.send(speedMultiplier) }
    }

    // MARK: - State

    private var locations: [CLLocation] = []
    private var currentIndex = 0
    private var timer: Timer?

    // MARK: - Public

    func load(gpxFileURL: URL) -> Bool {
        let parser = GPXParser()
        let parsed = parser.parse(fileURL: gpxFileURL)
        guard !parsed.isEmpty else { return false }
        locations = parsed
        currentIndex = 0
        progressPublisher.send(0.0)
        return true
    }

    func load(locations: [CLLocation]) {
        self.locations = locations
        currentIndex = 0
        progressPublisher.send(0.0)
    }

    func play() {
        guard !locations.isEmpty else { return }
        guard !isPlayingPublisher.value else { return }

        isPlayingPublisher.send(true)
        scheduleNext()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isPlayingPublisher.send(false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentIndex = 0
        progressPublisher.send(0.0)
        isPlayingPublisher.send(false)
    }

    func reset() {
        stop()
        locations = []
    }

    // MARK: - Private

    private func scheduleNext() {
        guard currentIndex < locations.count else {
            // Reached end
            stop()
            return
        }

        let location = locations[currentIndex]
        simulatedLocationPublisher.send(location)

        let progress = Double(currentIndex) / Double(max(1, locations.count - 1))
        progressPublisher.send(progress)

        currentIndex += 1

        guard currentIndex < locations.count else {
            stop()
            return
        }

        // Calculate interval to next point
        let nextLocation = locations[currentIndex]
        var interval = nextLocation.timestamp.timeIntervalSince(location.timestamp)

        // Fallback: if timestamps are invalid, use distance-based interval
        if interval <= 0 {
            let distance = location.distance(from: nextLocation)
            interval = distance / 13.9 // ~50 km/h
        }

        // Apply speed multiplier
        interval /= max(0.1, speedMultiplier)

        // Clamp to reasonable range
        interval = max(0.05, min(5.0, interval))

        timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            self?.scheduleNext()
        }
    }
}
