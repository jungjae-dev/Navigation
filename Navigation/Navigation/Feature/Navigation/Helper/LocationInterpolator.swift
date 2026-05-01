import CoreLocation

/// 60fps 위치/방향 보간기
/// GPS 업데이트(1Hz) 사이를 CADisplayLink(60Hz)로 부드럽게 채움
final class LocationInterpolator {

    struct InterpolatedResult {
        let coordinate: CLLocationCoordinate2D
        let heading: CLLocationDirection
    }

    // MARK: - State

    private var previous: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private var target: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private var previousHeading: CLLocationDirection = 0
    private var targetHeading: CLLocationDirection = 0
    private var startTime: Date = .now
    private let duration: TimeInterval = 1.0  // GPS 업데이트 간격

    private var isInitialized = false

    // MARK: - Set Target

    /// 새 GPS 위치 도착 시 호출 (1초마다)
    func setTarget(_ coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        if isInitialized {
            previous = target
            previousHeading = targetHeading
        } else {
            previous = coordinate
            previousHeading = heading
            isInitialized = true
        }

        target = coordinate
        targetHeading = heading
        startTime = .now
    }

    // MARK: - Interpolate

    /// CADisplayLink 콜백에서 매 프레임 호출 (60fps)
    func interpolate() -> InterpolatedResult {
        guard isInitialized else {
            return InterpolatedResult(coordinate: target, heading: targetHeading)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let t = min(max(elapsed / duration, 0), 1)

        // 좌표 선형 보간
        let lat = previous.latitude + (target.latitude - previous.latitude) * t
        let lon = previous.longitude + (target.longitude - previous.longitude) * t

        // heading 최단호 보간
        let delta = ((targetHeading - previousHeading + 540).truncatingRemainder(dividingBy: 360)) - 180
        let heading = previousHeading + delta * t

        return InterpolatedResult(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            heading: (heading + 360).truncatingRemainder(dividingBy: 360)
        )
    }

    // MARK: - Reset

    /// 백그라운드 복귀 시 점프 방지
    func resetTo(_ coordinate: CLLocationCoordinate2D, _ heading: CLLocationDirection) {
        previous = coordinate
        target = coordinate
        previousHeading = heading
        targetHeading = heading
        isInitialized = true
    }
}
