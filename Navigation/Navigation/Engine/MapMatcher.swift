import CoreLocation

/// 폴리라인 스냅 맵매칭
/// GPS 좌표를 경로 폴리라인 위에 투영하여 도로 위 위치를 반환
final class MapMatcher {

    // MARK: - Configuration

    private let threshold: CLLocationDistance = 50          // 매칭 거리 임계값 (m)
    private let maxAngleDelta: CLLocationDirection = 90     // 방향 검증 각도 (°)
    private let searchWindow: Int = 10                      // ±N 세그먼트 탐색

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
    func match(_ gps: GPSData) -> MatchResult {
        guard polyline.count >= 2 else {
            return MatchResult(
                isMatched: false,
                coordinate: gps.coordinate,
                segmentIndex: 0,
                distanceFromRoute: .infinity,
                headingDelta: 0
            )
        }

        // 탐색 범위: currentSegmentIndex ± searchWindow
        let segmentCount = polyline.count - 1
        let searchStart = max(0, currentSegmentIndex - searchWindow)
        let searchEnd = min(segmentCount - 1, currentSegmentIndex + searchWindow)

        var bestProjection = gps.coordinate
        var bestDistance: CLLocationDistance = .infinity
        var bestSegmentIndex = currentSegmentIndex
        var bestSegmentHeading: CLLocationDirection = 0

        for i in searchStart...searchEnd {
            let p1 = polyline[i]
            let p2 = polyline[i + 1]

            let (projection, distance) = projectPointOnSegment(
                point: gps.coordinate, segStart: p1, segEnd: p2
            )

            if distance < bestDistance {
                bestDistance = distance
                bestProjection = projection
                bestSegmentIndex = i
                bestSegmentHeading = bearing(from: p1, to: p2)
            }
        }

        // 거리 검증
        guard bestDistance <= threshold else {
            return MatchResult(
                isMatched: false,
                coordinate: gps.coordinate,
                segmentIndex: bestSegmentIndex,
                distanceFromRoute: bestDistance,
                headingDelta: angleDelta(gps.heading, bestSegmentHeading)
            )
        }

        // 방향 검증 (도보 모드 또는 저속 시 스킵)
        let headingDelta = angleDelta(gps.heading, bestSegmentHeading)
        let skipHeadingCheck = transportMode == .walking || gps.speed < 1.4  // < 5km/h

        if !skipHeadingCheck && headingDelta > maxAngleDelta {
            return MatchResult(
                isMatched: false,
                coordinate: gps.coordinate,
                segmentIndex: bestSegmentIndex,
                distanceFromRoute: bestDistance,
                headingDelta: headingDelta
            )
        }

        // 매칭 성공 → segmentIndex 갱신
        currentSegmentIndex = bestSegmentIndex

        return MatchResult(
            isMatched: true,
            coordinate: bestProjection,
            segmentIndex: bestSegmentIndex,
            distanceFromRoute: bestDistance,
            headingDelta: headingDelta
        )
    }

    /// 새 경로로 리셋 (재탐색 시)
    func reset(polyline: [CLLocationCoordinate2D]) {
        // MapMatcher는 let polyline이라 새 인스턴스 생성 필요
        // NavigationEngine에서 새 MapMatcher를 생성하는 방식으로 처리
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
            let dist = distanceInMeters(from: point, to: segStart)
            return (segStart, dist)
        }

        // 투영 비율 t (0~1 clamp)
        let t = max(0, min(1, (bx * ax + by * ay) / segLenSq))

        // 투영점
        let projection = CLLocationCoordinate2D(
            latitude: segStart.latitude + ay * t,
            longitude: segStart.longitude + ax * t
        )

        let dist = distanceInMeters(from: point, to: projection)
        return (projection, dist)
    }

    // MARK: - Geometry Helpers

    /// 두 좌표 간 방위각 (0~360)
    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 두 각도의 최소 차이 (0~180)
    private func angleDelta(_ a: CLLocationDirection, _ b: CLLocationDirection) -> CLLocationDirection {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    /// 두 좌표 간 거리 (미터)
    private func distanceInMeters(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
}
