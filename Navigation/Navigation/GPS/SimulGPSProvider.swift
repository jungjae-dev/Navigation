import CoreLocation
import Combine

/// 가상 주행 GPS Provider
/// - 경로 폴리라인 위를 설정 속도로 자동 이동
/// - 1초마다 GPSData 발행
/// - 속도 배율 변경 가능 (0.5x, 1x, 2x, 4x)
final class SimulGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsSubject.eraseToAnyPublisher()
    }

    // MARK: - Playback State

    enum PlayState: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    let playStatePublisher = CurrentValueSubject<PlayState, Never>(.idle)
    let progressPublisher = CurrentValueSubject<Double, Never>(0)
    let speedMultiplierPublisher = CurrentValueSubject<Double, Never>(1.0)

    // MARK: - Configuration

    private static let defaultSpeedMPS: Double = 13.9   // ~50 km/h
    private static let walkingSpeedMPS: Double = 1.4    // ~5 km/h
    private let speedMultipliers: [Double] = [0.5, 1.0, 2.0, 4.0]

    // MARK: - Private

    private let gpsSubject = PassthroughSubject<GPSData, Never>()
    private var polyline: [CLLocationCoordinate2D] = []
    private var segmentDistances: [CLLocationDistance] = []
    private var totalDistance: CLLocationDistance = 0
    private var traveledDistance: CLLocationDistance = 0
    private var baseSpeedMPS: Double = SimulGPSProvider.defaultSpeedMPS

    private var timer: Timer?
    private let tickInterval: TimeInterval = 1.0

    // MARK: - Load

    func load(polyline: [CLLocationCoordinate2D], transportMode: TransportMode = .automobile) {
        stop()

        self.polyline = polyline
        baseSpeedMPS = transportMode == .walking
            ? SimulGPSProvider.walkingSpeedMPS
            : SimulGPSProvider.defaultSpeedMPS

        precalculateSegments()
        playStatePublisher.send(.idle)
        progressPublisher.send(0)
    }

    // MARK: - GPSProviding

    func start() {
        play()
    }

    func stop() {
        playStatePublisher.send(.idle)
        stopTimer()
        traveledDistance = 0
        progressPublisher.send(0)
    }

    // MARK: - Playback Control

    func play() {
        guard !polyline.isEmpty else { return }

        if playStatePublisher.value == .finished {
            traveledDistance = 0
            progressPublisher.send(0)
        }

        playStatePublisher.send(.playing)
        startTimer()

        // 첫 위치 즉시 발행
        emitCurrentLocation()
    }

    func pause() {
        guard playStatePublisher.value == .playing else { return }
        playStatePublisher.send(.paused)
        stopTimer()
    }

    func cycleSpeed() {
        let current = speedMultiplierPublisher.value
        guard let currentIndex = speedMultipliers.firstIndex(of: current) else {
            speedMultiplierPublisher.send(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % speedMultipliers.count
        speedMultiplierPublisher.send(speedMultipliers[nextIndex])
    }

    // MARK: - Timer

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

    // MARK: - Tick

    private func tick() {
        guard playStatePublisher.value == .playing, totalDistance > 0 else { return }

        let effectiveSpeed = baseSpeedMPS * speedMultiplierPublisher.value
        let distanceDelta = effectiveSpeed * tickInterval

        traveledDistance += distanceDelta

        if traveledDistance >= totalDistance {
            traveledDistance = totalDistance
            emitCurrentLocation()
            playStatePublisher.send(.finished)
            stopTimer()
            return
        }

        emitCurrentLocation()
    }

    // MARK: - Emit Location

    private func emitCurrentLocation() {
        guard polyline.count >= 2 else { return }

        let (coordinate, segmentIndex) = interpolatePosition()
        let heading = calculateHeading(at: segmentIndex)
        let effectiveSpeed = baseSpeedMPS * speedMultiplierPublisher.value

        let gpsData = GPSData(
            coordinate: coordinate,
            heading: heading,
            speed: effectiveSpeed,
            accuracy: 5.0,
            timestamp: Date(),
            isValid: true
        )

        gpsSubject.send(gpsData)

        let progress = totalDistance > 0 ? traveledDistance / totalDistance : 0
        progressPublisher.send(min(progress, 1.0))
    }

    // MARK: - Position Calculation

    private func interpolatePosition() -> (CLLocationCoordinate2D, Int) {
        var accumulated: CLLocationDistance = 0

        for i in 0..<segmentDistances.count {
            let segDist = segmentDistances[i]
            if accumulated + segDist >= traveledDistance {
                let t = segDist > 0 ? (traveledDistance - accumulated) / segDist : 0
                let from = polyline[i]
                let to = polyline[i + 1]
                let lat = from.latitude + (to.latitude - from.latitude) * t
                let lon = from.longitude + (to.longitude - from.longitude) * t
                return (CLLocationCoordinate2D(latitude: lat, longitude: lon), i)
            }
            accumulated += segDist
        }

        // 끝점
        return (polyline[polyline.count - 1], max(0, segmentDistances.count - 1))
    }

    private func calculateHeading(at segmentIndex: Int) -> CLLocationDirection {
        guard segmentIndex < polyline.count - 1 else {
            return 0
        }
        return bearing(from: polyline[segmentIndex], to: polyline[segmentIndex + 1])
    }

    // MARK: - Helpers

    private func precalculateSegments() {
        segmentDistances = []
        totalDistance = 0

        guard polyline.count >= 2 else { return }

        for i in 0..<(polyline.count - 1) {
            let from = CLLocation(latitude: polyline[i].latitude, longitude: polyline[i].longitude)
            let to = CLLocation(latitude: polyline[i + 1].latitude, longitude: polyline[i + 1].longitude)
            let dist = from.distance(from: to)
            segmentDistances.append(dist)
            totalDistance += dist
        }
    }

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
