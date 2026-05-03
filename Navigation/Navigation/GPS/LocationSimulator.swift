import Foundation
import CoreLocation
import Combine

/// CLLocation 배열을 타이밍에 맞게 재생하는 공통 시뮬레이터
/// SimulGPSProvider, FileGPSProvider 모두 이 클래스를 사용
final class LocationSimulator {

    // MARK: - Publishers

    let simulatedLocationPublisher = PassthroughSubject<CLLocation, Never>()
    let isPlayingPublisher = CurrentValueSubject<Bool, Never>(false)
    let progressPublisher = CurrentValueSubject<Double, Never>(0.0)
    let speedMultiplierPublisher = CurrentValueSubject<Double, Never>(1.0)

    // MARK: - Configuration

    private let speeds: [Double] = [0.5, 1.0, 2.0, 4.0]

    var speedMultiplier: Double = 1.0 {
        didSet { speedMultiplierPublisher.send(speedMultiplier) }
    }

    // MARK: - State

    private var locations: [CLLocation] = []
    private var currentIndex = 0
    private var timer: Timer?
    private var isLooping: Bool = false

    // MARK: - Public: Load

    /// CLLocation 배열 직접 로드
    func load(locations: [CLLocation]) {
        self.locations = locations
        currentIndex = 0
        progressPublisher.send(0.0)
    }

    /// GPX 파일 파싱 → CLLocation 배열 로드
    func load(gpxFileURL: URL) -> Bool {
        let parser = GPXParser()
        let parsed = parser.parse(fileURL: gpxFileURL)
        guard !parsed.isEmpty else { return false }
        load(locations: parsed)
        return true
    }

    /// 폴리라인 + 속도로 CLLocation 배열 생성하여 로드 (가상 주행용)
    /// - Parameters:
    ///   - polyline: 좌표 배열
    ///   - speedMPS: 기본 속도 (m/s) — 이 속도로 1초 간격 위치 생성
    func load(polyline: [CLLocationCoordinate2D], speedMPS: Double = 13.9) {
        let generated = Self.generateLocations(polyline: polyline, speedMPS: speedMPS)
        load(locations: generated)
    }

    // MARK: - Public: Playback Control

    /// 재생 시작
    /// - Parameter loop: true면 끝까지 재생 후 처음부터 반복 (long-lived 용도 — File/가상주행)
    func play(loop: Bool = false) {
        guard !locations.isEmpty else { return }
        guard !isPlayingPublisher.value else { return }

        isLooping = loop
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
        isLooping = false
        currentIndex = 0
        progressPublisher.send(0.0)
        isPlayingPublisher.send(false)
    }

    func reset() {
        stop()
        locations = []
    }

    func cycleSpeed() {
        let idx = speeds.firstIndex(of: speedMultiplier) ?? 1
        speedMultiplier = speeds[(idx + 1) % speeds.count]
    }

    // MARK: - Private: Schedule

    private func scheduleNext() {
        guard currentIndex < locations.count else {
            handleEnd()
            return
        }

        let location = locations[currentIndex]
        simulatedLocationPublisher.send(location)

        let progress = Double(currentIndex) / Double(max(1, locations.count - 1))
        progressPublisher.send(progress)

        currentIndex += 1

        guard currentIndex < locations.count else {
            handleEnd()
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

    /// 마지막 좌표 도달 시 처리 — loop면 처음부터 다시, 아니면 정지
    private func handleEnd() {
        if isLooping {
            currentIndex = 0
            progressPublisher.send(0.0)
            scheduleNext()
        } else {
            reset()
        }
    }

    // MARK: - Static: Generate Locations from Polyline

    /// 폴리라인 + 속도 → 1초 간격의 CLLocation 배열 생성
    /// 각 위치는 속도/heading/timestamp가 계산됨
    static func generateLocations(
        polyline: [CLLocationCoordinate2D],
        speedMPS: Double
    ) -> [CLLocation] {
        guard polyline.count >= 2, speedMPS > 0 else { return [] }

        // 세그먼트 거리 / 누적 거리 사전 계산
        var segmentDistances: [CLLocationDistance] = []
        var totalDistance: CLLocationDistance = 0
        for i in 0..<(polyline.count - 1) {
            let from = CLLocation(latitude: polyline[i].latitude, longitude: polyline[i].longitude)
            let to = CLLocation(latitude: polyline[i + 1].latitude, longitude: polyline[i + 1].longitude)
            let dist = from.distance(from: to)
            segmentDistances.append(dist)
            totalDistance += dist
        }

        guard totalDistance > 0 else { return [] }

        let totalSeconds = totalDistance / speedMPS
        let pointCount = max(2, Int(ceil(totalSeconds)) + 1)  // 1초 간격

        var locations: [CLLocation] = []
        let baseTime = Date()

        for tick in 0..<pointCount {
            let traveled = min(Double(tick) * speedMPS, totalDistance)
            let (coord, segIdx) = positionAt(
                distance: traveled,
                polyline: polyline,
                segmentDistances: segmentDistances
            )
            let heading = bearing(
                from: polyline[segIdx],
                to: polyline[min(segIdx + 1, polyline.count - 1)]
            )
            let timestamp = baseTime.addingTimeInterval(Double(tick))

            let location = CLLocation(
                coordinate: coord,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: heading,
                speed: speedMPS,
                timestamp: timestamp
            )
            locations.append(location)
        }

        return locations
    }

    private static func positionAt(
        distance: CLLocationDistance,
        polyline: [CLLocationCoordinate2D],
        segmentDistances: [CLLocationDistance]
    ) -> (CLLocationCoordinate2D, Int) {
        var accumulated: CLLocationDistance = 0
        for i in 0..<segmentDistances.count {
            let segDist = segmentDistances[i]
            if accumulated + segDist >= distance {
                let t = segDist > 0 ? (distance - accumulated) / segDist : 0
                let from = polyline[i]
                let to = polyline[i + 1]
                let lat = from.latitude + (to.latitude - from.latitude) * t
                let lon = from.longitude + (to.longitude - from.longitude) * t
                return (CLLocationCoordinate2D(latitude: lat, longitude: lon), i)
            }
            accumulated += segDist
        }
        return (polyline[polyline.count - 1], max(0, segmentDistances.count - 1))
    }

    private static func bearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let b = atan2(y, x) * 180 / .pi

        return (b + 360).truncatingRemainder(dividingBy: 360)
    }
}
