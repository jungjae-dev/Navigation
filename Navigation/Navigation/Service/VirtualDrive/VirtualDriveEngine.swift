import Foundation
import MapKit
import CoreLocation
import Combine

/// Drives a virtual location along an MKRoute polyline for simulation/testing
final class VirtualDriveEngine {

    // MARK: - State

    enum PlayState: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    // MARK: - Publishers

    let simulatedLocationPublisher = CurrentValueSubject<CLLocation?, Never>(nil)
    let simulatedHeadingPublisher = CurrentValueSubject<CLLocationDirection, Never>(0)
    let playStatePublisher = CurrentValueSubject<PlayState, Never>(.idle)
    let progressPublisher = CurrentValueSubject<Double, Never>(0)
    let speedMultiplierPublisher = CurrentValueSubject<Double, Never>(1.0)

    // MARK: - Configuration

    private static let defaultSpeedMPS: Double = 13.9 // ~50 km/h
    private static let walkingSpeedMPS: Double = 1.4 // ~5 km/h
    private let speedMultipliers: [Double] = [0.5, 1.0, 2.0, 4.0]

    // MARK: - State

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var segmentDistances: [CLLocationDistance] = []
    private var totalDistance: CLLocationDistance = 0
    private var traveledDistance: CLLocationDistance = 0
    private var currentSegmentIndex: Int = 0
    private var currentSegmentProgress: Double = 0
    private var baseSpeedMPS: Double = VirtualDriveEngine.defaultSpeedMPS

    private var timer: Timer?
    private let tickInterval: TimeInterval = 1.0 / 30.0 // 30 Hz

    // MARK: - Public: Load Route

    /// Load an MKRoute for virtual driving
    func load(route: MKRoute, transportMode: TransportMode = .automobile) {
        stop()

        routeCoordinates = route.polyline.coordinates
        baseSpeedMPS = transportMode == .walking
            ? VirtualDriveEngine.walkingSpeedMPS
            : VirtualDriveEngine.defaultSpeedMPS

        precalculateSegments()
        playStatePublisher.send(.idle)
        progressPublisher.send(0)
    }

    // MARK: - Public: Playback Control

    func play() {
        guard !routeCoordinates.isEmpty else { return }

        if playStatePublisher.value == .finished {
            reset()
        }

        playStatePublisher.send(.playing)
        startTimer()

        // Emit first location
        emitCurrentLocation()
    }

    func pause() {
        guard playStatePublisher.value == .playing else { return }
        playStatePublisher.send(.paused)
        stopTimer()
    }

    func stop() {
        playStatePublisher.send(.idle)
        stopTimer()
        reset()
    }

    func reset() {
        traveledDistance = 0
        currentSegmentIndex = 0
        currentSegmentProgress = 0
        progressPublisher.send(0)
        simulatedLocationPublisher.send(nil)
        simulatedHeadingPublisher.send(0)
    }

    /// Cycle through speed multipliers: 0.5x → 1x → 2x → 4x → 0.5x
    func cycleSpeed() {
        let current = speedMultiplierPublisher.value
        guard let currentIndex = speedMultipliers.firstIndex(of: current) else {
            speedMultiplierPublisher.send(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % speedMultipliers.count
        speedMultiplierPublisher.send(speedMultipliers[nextIndex])
    }

    func setSpeedMultiplier(_ multiplier: Double) {
        let clamped = max(0.5, min(4.0, multiplier))
        speedMultiplierPublisher.send(clamped)
    }

    // MARK: - Private: Segment Precalculation

    private func precalculateSegments() {
        segmentDistances = []
        totalDistance = 0

        guard routeCoordinates.count >= 2 else { return }

        for i in 0..<(routeCoordinates.count - 1) {
            let from = CLLocation(latitude: routeCoordinates[i].latitude, longitude: routeCoordinates[i].longitude)
            let to = CLLocation(latitude: routeCoordinates[i + 1].latitude, longitude: routeCoordinates[i + 1].longitude)
            let dist = from.distance(from: to)
            segmentDistances.append(dist)
            totalDistance += dist
        }
    }

    // MARK: - Private: Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private: Tick

    private func tick() {
        guard playStatePublisher.value == .playing else { return }
        guard totalDistance > 0 else { return }

        let effectiveSpeed = baseSpeedMPS * speedMultiplierPublisher.value
        let distanceDelta = effectiveSpeed * tickInterval

        traveledDistance += distanceDelta

        // Check if finished
        if traveledDistance >= totalDistance {
            traveledDistance = totalDistance
            emitCurrentLocation()
            playStatePublisher.send(.finished)
            stopTimer()
            return
        }

        // Find current segment
        updateCurrentSegment()
        emitCurrentLocation()
    }

    private func updateCurrentSegment() {
        var accumulated: CLLocationDistance = 0

        for i in 0..<segmentDistances.count {
            let segDist = segmentDistances[i]
            if accumulated + segDist >= traveledDistance {
                currentSegmentIndex = i
                currentSegmentProgress = segDist > 0
                    ? (traveledDistance - accumulated) / segDist
                    : 0
                return
            }
            accumulated += segDist
        }

        // At the end
        currentSegmentIndex = max(0, segmentDistances.count - 1)
        currentSegmentProgress = 1.0
    }

    // MARK: - Private: Emit Location

    private func emitCurrentLocation() {
        guard currentSegmentIndex < routeCoordinates.count - 1 else {
            // Emit last coordinate
            if let last = routeCoordinates.last {
                let location = CLLocation(
                    coordinate: last,
                    altitude: 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    course: simulatedHeadingPublisher.value,
                    speed: baseSpeedMPS * speedMultiplierPublisher.value,
                    timestamp: Date()
                )
                simulatedLocationPublisher.send(location)
                progressPublisher.send(1.0)
            }
            return
        }

        let from = routeCoordinates[currentSegmentIndex]
        let to = routeCoordinates[currentSegmentIndex + 1]
        let t = currentSegmentProgress

        // Interpolate position
        let lat = from.latitude + (to.latitude - from.latitude) * t
        let lon = from.longitude + (to.longitude - from.longitude) * t
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        // Calculate heading (bearing from → to)
        let heading = bearing(from: from, to: to)
        simulatedHeadingPublisher.send(heading)

        let effectiveSpeed = baseSpeedMPS * speedMultiplierPublisher.value
        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: heading,
            speed: effectiveSpeed,
            timestamp: Date()
        )
        simulatedLocationPublisher.send(location)

        // Update progress
        let progress = totalDistance > 0 ? traveledDistance / totalDistance : 0
        progressPublisher.send(min(progress, 1.0))
    }

    // MARK: - Private: Bearing

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
