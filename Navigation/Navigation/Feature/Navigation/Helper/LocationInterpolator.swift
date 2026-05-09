import CoreLocation

/// 60fps 위치/방향/고도 보간기
/// GPS 업데이트(1Hz) 사이를 CADisplayLink(60Hz)로 부드럽게 채움
final class LocationInterpolator {

    struct InterpolatedResult {
        let coordinate: CLLocationCoordinate2D
        let heading: CLLocationDirection
        let altitude: CLLocationDistance
    }

    // MARK: - State

    private var previous: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private var target: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private var previousHeading: CLLocationDirection = 0
    private var targetHeading: CLLocationDirection = 0
    private var previousAltitude: CLLocationDistance = 500
    private var targetAltitude: CLLocationDistance = 500
    private var startTime: Date = .now
    private let duration: TimeInterval = 1.0  // GPS 업데이트 간격

    private var isInitialized = false

    // MARK: - Set Target

    /// 새 GPS 위치 도착 시 호출 (1초마다)
    func setTarget(_ coordinate: CLLocationCoordinate2D, heading: CLLocationDirection, altitude: CLLocationDistance = 0) {
        if isInitialized {
            // 이전 목적지(target)가 아닌 현재 시각적 위치를 previous로 사용:
            // previous = target 이면 setTarget 직후 t=0에서 아이콘이 이전 목적지로
            // 순간이동한 뒤 새 목적지로 이동하는 점프가 발생함.
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(max(elapsed / duration, 0), 1)
            previous = previous.interpolated(to: target, t: t)
            let delta = ((targetHeading - previousHeading + 540).truncatingRemainder(dividingBy: 360)) - 180
            previousHeading = (previousHeading + delta * t + 360).truncatingRemainder(dividingBy: 360)
            previousAltitude = previousAltitude + (targetAltitude - previousAltitude) * t
        } else {
            previous = coordinate
            previousHeading = heading
            previousAltitude = altitude
            isInitialized = true
        }

        target = coordinate
        targetHeading = heading
        targetAltitude = altitude
        startTime = .now
    }

    // MARK: - Interpolate

    /// CADisplayLink 콜백에서 매 프레임 호출 (60fps)
    func interpolate() -> InterpolatedResult {
        guard isInitialized else {
            return InterpolatedResult(coordinate: target, heading: targetHeading, altitude: targetAltitude)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let t = min(max(elapsed / duration, 0), 1)

        let coordinate = previous.interpolated(to: target, t: t)

        let delta = ((targetHeading - previousHeading + 540).truncatingRemainder(dividingBy: 360)) - 180
        let heading = previousHeading + delta * t

        let altitude = previousAltitude + (targetAltitude - previousAltitude) * t

        return InterpolatedResult(
            coordinate: coordinate,
            heading: (heading + 360).truncatingRemainder(dividingBy: 360),
            altitude: altitude
        )
    }

    // MARK: - Reset

    /// 백그라운드 복귀 시 점프 방지
    func resetTo(_ coordinate: CLLocationCoordinate2D, _ heading: CLLocationDirection, altitude: CLLocationDistance = 0) {
        previous = coordinate
        target = coordinate
        previousHeading = heading
        targetHeading = heading
        previousAltitude = altitude
        targetAltitude = altitude
        isInitialized = true
    }
}
