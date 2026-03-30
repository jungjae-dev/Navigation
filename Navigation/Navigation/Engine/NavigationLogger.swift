import Foundation
import CoreLocation
import os

/// 네비게이션 엔진 디버그 로그 시스템
/// 개발자 메뉴에서 로그 레벨 변경 가능
final class NavigationLogger {

    static let shared = NavigationLogger()

    // MARK: - Log Level

    enum Level: Int, Comparable {
        case off = 0
        case stateChangesOnly = 1   // 상태 전이, 스텝 전진, 음성 트리거, 이탈 판정
        case everyTick = 2          // 매초 전체 데이터

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var level: Level = .everyTick   // 개발 중 기본값, 릴리즈 시 .off

    private let logger = Logger(subsystem: "com.routin.navigation", category: "Engine")

    private init() {}

    // MARK: - GPS

    func logGPS(_ gps: GPSData) {
        guard level >= .everyTick else { return }
        let validStr = gps.isValid ? "valid" : "invalid"
        let speedKmh = String(format: "%.1f", gps.speed * 3.6)
        logger.debug("[GPS] \(validStr) coord=(\(String(format: "%.6f", gps.coordinate.latitude)), \(String(format: "%.6f", gps.coordinate.longitude))) heading=\(String(format: "%.1f", gps.heading)) speed=\(speedKmh)km/h accuracy=\(String(format: "%.1f", gps.accuracy))m")
    }

    // MARK: - Match

    func logMatch(_ result: MatchResult) {
        guard level >= .everyTick else { return }
        let matchStr = result.isMatched ? "✅" : "❌"
        logger.debug("[Match] \(matchStr) coord=(\(String(format: "%.6f", result.coordinate.latitude)), \(String(format: "%.6f", result.coordinate.longitude))) seg=\(result.segmentIndex) dist=\(String(format: "%.1f", result.distanceFromRoute))m Δ=\(String(format: "%.1f", result.headingDelta))°")
    }

    // MARK: - Track

    func logTrackProgress(stepIndex: Int, totalSteps: Int, distanceToManeuver: CLLocationDistance, remainingDistance: CLLocationDistance, eta: Date) {
        guard level >= .everyTick else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let etaStr = formatter.string(from: eta)
        let remainingKm = String(format: "%.1f", remainingDistance / 1000)
        logger.debug("[Track] step=\(stepIndex)/\(totalSteps) toManeuver=\(String(format: "%.0f", distanceToManeuver))m remaining=\(remainingKm)km eta=\(etaStr)")
    }

    func logStepAdvance(from: Int, to: Int, instruction: String) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[Track] ★ Step \(from) → Step \(to) (\(instruction))")
    }

    // MARK: - State

    func logStateChange(from: NavigationState, to: NavigationState) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[State] \(String(describing: from)) → \(String(describing: to))")
    }

    // MARK: - Voice

    func logVoiceTrigger(stepIndex: Int, distance: CLLocationDistance, text: String) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[Voice] step=\(stepIndex) \(String(format: "%.0f", distance))m: \(text)")
    }

    // MARK: - Off Route

    func logOffRoute(consecutiveFailures: Int, isOffRoute: Bool) {
        guard level >= .stateChangesOnly else { return }
        if isOffRoute {
            logger.warning("[Match] ❌ offRoute! consecutiveFailures=\(consecutiveFailures)")
        }
    }

    // MARK: - Dead Reckoning

    func logDeadReckoning(active: Bool, estimatedDistance: CLLocationDistance? = nil) {
        guard level >= .everyTick else { return }
        if active, let dist = estimatedDistance {
            logger.debug("[DR] active Δd=\(String(format: "%.1f", dist))m")
        } else {
            logger.debug("[DR] inactive")
        }
    }

    // MARK: - Route

    func logRouteConverted(provider: RouteProvider, stepCount: Int, polylineCount: Int) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[Route] provider=\(provider.rawValue) steps=\(stepCount) polyline=\(polylineCount)pts")
    }

    func logRouteStep(index: Int, instruction: String, turnType: TurnType, roadName: String?, polylineCount: Int, rawType: Int? = nil) {
        guard level >= .stateChangesOnly else { return }
        let road = roadName ?? "-"
        let rawTypeStr = rawType.map { " rawType=\($0)" } ?? ""
        logger.info("[Step \(index)] \(instruction) | turnType=\(String(describing: turnType))\(rawTypeStr) | road=\(road) | polyline=\(polylineCount)pts")
    }
}
