import CoreLocation

/// 경로 이탈 감지
/// GPS valid일 때만 호출 (GPS invalid 시 엔진이 호출하지 않음)
final class OffRouteDetector {

    // MARK: - Configuration

    private let requiredFailures: Int = 3                       // 이탈 확정 연속 횟수
    private let startDistanceProtection: CLLocationDistance = 35 // 출발 거리 보호 (m)
    private let startTimeProtection: TimeInterval = 5           // 출발 시간 보호 (초)
    private let accuracyThreshold: CLLocationAccuracy = CLLocation.navigationAccuracyThreshold

    // MARK: - State

    private(set) var consecutiveFailures: Int = 0
    private var navigationStartTime: Date?
    private var startCoordinate: CLLocationCoordinate2D?

    private let logger = NavigationLogger.shared

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
        if let startTime = navigationStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < startTimeProtection {
                if !matchResult.isMatched {
                    logger.logOffRouteProtected(
                        reason: "startTime \(String(format: "%.1f", elapsed))s < \(Int(startTimeProtection))s"
                    )
                }
                return false
            }
        }

        // 보호 조건 2: 출발 후 35m 이내 → 보류
        if let startCoord = startCoordinate {
            let distFromStart = startCoord.distance(to: matchResult.coordinate)
            if distFromStart < startDistanceProtection {
                if !matchResult.isMatched {
                    logger.logOffRouteProtected(
                        reason: "startDistance \(String(format: "%.1f", distFromStart))m < \(Int(startDistanceProtection))m"
                    )
                }
                return false
            }
        }

        // 보호 조건 3: GPS 정확도 불량 → 보류
        if gpsAccuracy > accuracyThreshold {
            if !matchResult.isMatched {
                logger.logOffRouteProtected(
                    reason: "accuracy \(String(format: "%.1f", gpsAccuracy))m > \(Int(accuracyThreshold))m"
                )
            }
            return false
        }

        // 이탈 판정
        if matchResult.isMatched {
            consecutiveFailures = 0
            return false
        } else {
            consecutiveFailures += 1
            let confirmed = consecutiveFailures >= requiredFailures
            if confirmed {
                logger.logOffRouteConfirmed(consecutiveFailures: consecutiveFailures)
            }
            return confirmed
        }
    }

    /// 상태 리셋 (재탐색 후)
    func reset() {
        consecutiveFailures = 0
    }

}
