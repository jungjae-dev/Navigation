import CoreLocation

/// 경로 이탈 감지
/// GPS valid일 때만 호출 (GPS invalid 시 엔진이 호출하지 않음)
final class OffRouteDetector {

    // MARK: - Configuration

    private let requiredFailures: Int = 3                       // 이탈 확정 연속 횟수
    private let startDistanceProtection: CLLocationDistance = 35 // 출발 거리 보호 (m)
    private let startTimeProtection: TimeInterval = 5           // 출발 시간 보호 (초)
    private let accuracyThreshold: CLLocationAccuracy = 120     // GPS 정확도 보류 임계값 (m)

    // MARK: - State

    private(set) var consecutiveFailures: Int = 0
    private var navigationStartTime: Date?
    private var startCoordinate: CLLocationCoordinate2D?

    // MARK: - Init

    init() {}

    // MARK: - Start

    /// 주행 시작 시 호출 (보호 조건용 기준점 설정)
    func start(at coordinate: CLLocationCoordinate2D) {
        navigationStartTime = Date()
        startCoordinate = coordinate
        consecutiveFailures = 0
    }

    // MARK: - Update

    /// 맵매칭 결과 + GPS 정확도를 받아 이탈 여부 판정
    /// - Returns: true이면 이탈 확정
    func update(matchResult: MatchResult, gpsAccuracy: CLLocationAccuracy) -> Bool {
        // 보호 조건 1: 출발 후 5초 이내 → 보류
        if let startTime = navigationStartTime,
           Date().timeIntervalSince(startTime) < startTimeProtection {
            return false
        }

        // 보호 조건 2: 출발 후 35m 이내 → 보류
        if let startCoord = startCoordinate {
            let distFromStart = distanceInMeters(from: startCoord, to: matchResult.coordinate)
            if distFromStart < startDistanceProtection {
                return false
            }
        }

        // 보호 조건 3: GPS 정확도 불량 → 보류
        if gpsAccuracy > accuracyThreshold {
            return false
        }

        // 이탈 판정
        if matchResult.isMatched {
            consecutiveFailures = 0
            return false
        } else {
            consecutiveFailures += 1
            return consecutiveFailures >= requiredFailures
        }
    }

    /// 상태 리셋 (재탐색 후)
    func reset() {
        consecutiveFailures = 0
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
}
