import CoreLocation

/// Dead Reckoning — GPS 손실 시 폴리라인 위 추정 이동
/// 마지막 유효 속도/위치를 기반으로 경과 시간만큼 폴리라인을 따라 전진
final class DeadReckoning {

    // MARK: - State

    private let polyline: [CLLocationCoordinate2D]
    private var lastValidPosition: CLLocationCoordinate2D?
    private var lastValidSpeed: CLLocationSpeed = 0
    private var lastValidSegmentIndex: Int = 0
    private var lastValidTime: Date?

    /// 누적 추정 거리 (마지막 유효 위치로부터)
    private var accumulatedDistance: CLLocationDistance = 0

    // MARK: - Init

    init(polyline: [CLLocationCoordinate2D]) {
        self.polyline = polyline
    }

    // MARK: - Update Last Valid

    /// 맵매칭 성공 시 마지막 유효 상태 갱신
    func updateLastValid(
        position: CLLocationCoordinate2D,
        speed: CLLocationSpeed,
        segmentIndex: Int
    ) {
        lastValidPosition = position
        lastValidSpeed = speed
        lastValidSegmentIndex = segmentIndex
        lastValidTime = Date()
        accumulatedDistance = 0
    }

    // MARK: - Estimate

    /// GPS invalid 시 호출 — 추정 좌표 반환
    func estimate(currentTime: Date) -> DeadReckoningResult? {
        guard lastValidPosition != nil,
              let lastTime = lastValidTime,
              lastValidSpeed > 0,
              polyline.count >= 2 else {
            return nil
        }

        // 경과 시간으로 이동 거리 계산
        let elapsed = currentTime.timeIntervalSince(lastTime)
        let totalDistance = lastValidSpeed * elapsed

        // 폴리라인 위에서 totalDistance만큼 전진
        return advanceOnPolyline(
            fromSegmentIndex: lastValidSegmentIndex,
            distance: totalDistance
        )
    }

    /// 리셋
    func reset() {
        lastValidPosition = nil
        lastValidSpeed = 0
        lastValidSegmentIndex = 0
        lastValidTime = nil
        accumulatedDistance = 0
    }

    // MARK: - Polyline Advance

    /// 폴리라인 위에서 지정 거리만큼 전진한 좌표 계산
    func advanceOnPolyline(
        fromSegmentIndex startIndex: Int,
        distance: CLLocationDistance
    ) -> DeadReckoningResult? {
        guard startIndex < polyline.count - 1 else { return nil }

        var remaining = distance
        var currentIndex = startIndex

        while currentIndex < polyline.count - 1 {
            let segStart = polyline[currentIndex]
            let segEnd = polyline[currentIndex + 1]
            let segLength = distanceInMeters(from: segStart, to: segEnd)

            if remaining <= segLength {
                // 이 세그먼트 내에서 전진
                let t = segLength > 0 ? remaining / segLength : 0
                let lat = segStart.latitude + (segEnd.latitude - segStart.latitude) * t
                let lon = segStart.longitude + (segEnd.longitude - segStart.longitude) * t
                let heading = bearing(from: segStart, to: segEnd)

                return DeadReckoningResult(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    heading: heading,
                    segmentIndex: currentIndex
                )
            }

            // 이 세그먼트를 지나감
            remaining -= segLength
            currentIndex += 1
        }

        // 폴리라인 끝에 도달
        let lastCoord = polyline[polyline.count - 1]
        let lastHeading: CLLocationDirection
        if polyline.count >= 2 {
            lastHeading = bearing(from: polyline[polyline.count - 2], to: lastCoord)
        } else {
            lastHeading = 0
        }

        return DeadReckoningResult(
            coordinate: lastCoord,
            heading: lastHeading,
            segmentIndex: max(0, polyline.count - 2)
        )
    }

    // MARK: - Helpers

    private func distanceInMeters(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let b = atan2(y, x) * 180 / .pi

        return (b + 360).truncatingRemainder(dividingBy: 360)
    }
}
