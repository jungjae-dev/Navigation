import CoreLocation

/// 폴리라인 스냅 맵매칭
/// GPS 좌표를 경로 폴리라인 위에 투영하여 도로 위 위치를 반환
final class MapMatcher {

    // MARK: - Configuration

    private let thresholdBase: CLLocationDistance = 35       // 기본 매칭 거리 (m)
    private let thresholdTimeFactor: TimeInterval = 1.0      // 속도에 곱할 시간 계수
    private let maxAngleDelta: CLLocationDirection = 90     // 방향 검증 각도 (°)

    // MARK: - State

    private let polyline: [CLLocationCoordinate2D]
    private let transportMode: TransportMode
    private(set) var currentSegmentIndex: Int = 0

    // MARK: - Init

    init(polyline: [CLLocationCoordinate2D], transportMode: TransportMode = .automobile) {
        self.polyline = polyline
        self.transportMode = transportMode
    }

    // MARK: - Match

    /// GPS 좌표를 폴리라인 위에 투영
    func match(_ location: CLLocation) -> MatchResult {
        let coordinate = location.coordinate
        let speed = location.safeSpeed
        let course = location.course

        guard polyline.count >= 2 else {
            return MatchResult(
                isMatched: false,
                coordinate: coordinate,
                segmentIndex: 0,
                distanceFromRoute: .infinity,
                headingDelta: 0,
                score: .infinity
            )
        }

        let segmentCount = polyline.count - 1

        // Forward only: currentSegmentIndex → 끝, 거리가 커지면 조기 종료
        var bestProjection = coordinate
        var bestDistance: CLLocationDistance = .infinity
        var bestSegmentIndex = currentSegmentIndex
        var bestSegmentHeading: CLLocationDirection = 0
        var prevDist: CLLocationDistance = .infinity

        for i in currentSegmentIndex..<segmentCount {
            let (projection, distance) = projectPointOnSegment(
                point: coordinate, segStart: polyline[i], segEnd: polyline[i + 1]
            )
            if distance < bestDistance {
                bestDistance = distance
                bestProjection = projection
                bestSegmentIndex = i
                bestSegmentHeading = MapGeometry.bearing(from: polyline[i], to: polyline[i + 1])
            } else if distance > prevDist {
                break
            }
            prevDist = distance
        }

        // 거리 검증: 도로폭/폴리라인 오차 기준(20m) + 1초 이동거리
        let threshold = thresholdBase + speed * thresholdTimeFactor
        guard bestDistance <= threshold else {
            let delta = abs(MapGeometry.angleDelta(course, bestSegmentHeading))
            return MatchResult(
                isMatched: false,
                coordinate: coordinate,
                segmentIndex: bestSegmentIndex,
                distanceFromRoute: bestDistance,
                headingDelta: delta,
                score: bestDistance
            )
        }

        // 방향 검증 스킵 조건:
        // - 도보 모드
        // - 저속(< 5km/h): course 부정확
        // - course < 0: GPS course 미확보 (첫 fix 전, 터널 등)
        let headingDelta = abs(MapGeometry.angleDelta(course, bestSegmentHeading))
        let skipHeadingCheck = transportMode == .walking
            || speed < 1.4
            || course < 0

        if !skipHeadingCheck && headingDelta > maxAngleDelta {
            return MatchResult(
                isMatched: false,
                coordinate: coordinate,
                segmentIndex: bestSegmentIndex,
                distanceFromRoute: bestDistance,
                headingDelta: headingDelta,
                score: bestDistance
            )
        }

        // 매칭 성공 → segmentIndex 갱신
        currentSegmentIndex = bestSegmentIndex

        return MatchResult(
            isMatched: true,
            coordinate: bestProjection,
            segmentIndex: bestSegmentIndex,
            distanceFromRoute: bestDistance,
            headingDelta: headingDelta,
            score: bestDistance
        )
    }

    // MARK: - Perpendicular Projection (수선의 발)

    /// 점 P를 선분 AB 위에 투영하여 가장 가까운 점과 거리를 반환
    func projectPointOnSegment(
        point: CLLocationCoordinate2D,
        segStart: CLLocationCoordinate2D,
        segEnd: CLLocationCoordinate2D
    ) -> (projection: CLLocationCoordinate2D, distance: CLLocationDistance) {
        // 선분 AB 벡터
        let ax = segEnd.longitude - segStart.longitude
        let ay = segEnd.latitude - segStart.latitude

        // 선분 AP 벡터
        let bx = point.longitude - segStart.longitude
        let by = point.latitude - segStart.latitude

        // 선분 길이의 제곱
        let segLenSq = ax * ax + ay * ay

        // 선분 길이가 0이면 (동일 점) → segStart 반환
        guard segLenSq > 0 else {
            return (segStart, point.distance(to: segStart))
        }

        // 투영 비율 t (0~1 clamp)
        let t = max(0, min(1, (bx * ax + by * ay) / segLenSq))

        // 투영점
        let projection = segStart.interpolated(to: segEnd, t: t)

        return (projection, point.distance(to: projection))
    }
}
