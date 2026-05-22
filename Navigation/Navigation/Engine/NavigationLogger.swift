import Foundation
import CoreLocation
import MapKit
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

    func logGPS(_ location: CLLocation) {
        guard level >= .everyTick else { return }
        let validStr = location.isGPSLoss ? "loss" : (location.isValid ? "valid" : "invalid")
        let speedKmh = String(format: "%.1f", location.safeSpeed * 3.6)
        let ts = String(format: "%.2f", location.timestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        logger.debug("[GPS] \(validStr) t=\(ts)s coord=(\(String(format: "%.6f", location.coordinate.latitude)), \(String(format: "%.6f", location.coordinate.longitude))) heading=\(String(format: "%.1f", location.course)) speed=\(speedKmh)km/h accuracy=\(String(format: "%.1f", location.horizontalAccuracy))m")
    }

    // MARK: - Display Position

    private var lastDisplayCoord: CLLocationCoordinate2D?
    private var lastDisplayTime: Date?

    func resetDisplayState() {
        lastDisplayCoord = nil
        lastDisplayTime = nil
    }

    func logDisplay(matchedPosition: CLLocationCoordinate2D, heading: CLLocationDirection, isMatched: Bool, isGPSLoss: Bool) {
        guard level >= .everyTick else { return }
        let matchStr = isMatched ? "matched" : "unmatched"
        let lossStr = isGPSLoss ? " [GPSLoss]" : ""
        let now = Date()
        let ts = String(format: "%.2f", now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        var intervalStr = ""
        if let last = lastDisplayTime {
            intervalStr = " dt=\(String(format: "%.2f", now.timeIntervalSince(last)))s"
        }
        lastDisplayTime = now
        var jumpStr = ""
        if let last = lastDisplayCoord {
            let dist = last.distance(to: matchedPosition)
            if dist > 1.0 {
                jumpStr = " jump=\(String(format: "%.1f", dist))m"
            }
        }
        lastDisplayCoord = matchedPosition
        logger.debug("[Display]\(lossStr) t=\(ts)s\(intervalStr) \(matchStr) coord=(\(String(format: "%.6f", matchedPosition.latitude)), \(String(format: "%.6f", matchedPosition.longitude))) heading=\(String(format: "%.1f", heading))\(jumpStr)")
    }

    // MARK: - Match

    func logMatch(_ result: MatchResult) {
        guard level >= .everyTick else { return }
        let matchStr = result.isMatched ? "✅" : "❌"
        let distStr = result.distanceFromRoute.isInfinite ? "inf" : String(format: "%.1f", result.distanceFromRoute)
        let scoreStr = result.score.isInfinite ? "inf" : String(format: "%.1f", result.score)
        logger.debug("[Match] \(matchStr) coord=(\(String(format: "%.6f", result.coordinate.latitude)), \(String(format: "%.6f", result.coordinate.longitude))) seg=\(result.segmentIndex) dist=\(distStr)m Δ=\(String(format: "%.1f", result.headingDelta))° score=\(scoreStr) thr=\(String(format: "%.1f", result.threshold))m")
    }

    // MARK: - Track

    private let etaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    func logTrackProgress(stepIndex: Int, totalSteps: Int, distanceToManeuver: CLLocationDistance, remainingDistance: CLLocationDistance, eta: Date) {
        guard level >= .everyTick else { return }
        let etaStr = etaFormatter.string(from: eta)
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

    // MARK: - Reroute (이탈 감지 + 재탐색 — `[Reroute]` 한 단어로 필터링)

    /// 이탈 확정 (3회 연속 매칭 실패 + 보호 조건 통과)
    func logOffRouteConfirmed(consecutiveFailures: Int) {
        guard level >= .stateChangesOnly else { return }
        logger.warning("[Reroute] ❌ off-route confirmed consecutiveFailures=\(consecutiveFailures)")
    }

    /// 매칭 실패했지만 보호 조건이 막은 경우 (어떤 조건이 막았는지 사유 표시)
    func logOffRouteProtected(reason: String) {
        guard level >= .everyTick else { return }
        logger.debug("[Reroute] ⚠️ protected — \(reason)")
    }

    func logRerouteStart(from coordinate: CLLocationCoordinate2D) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[Reroute] start from=(\(String(format: "%.6f", coordinate.latitude)), \(String(format: "%.6f", coordinate.longitude)))")
    }

    func logRerouteAttempt(attempt: Int, maxAttempts: Int) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[Reroute] attempt \(attempt)/\(maxAttempts)")
    }

    func logRerouteSuccess(provider: RouteProvider, stepCount: Int, polylineCount: Int) {
        guard level >= .stateChangesOnly else { return }
        logger.info("[Reroute] ✅ success provider=\(provider.rawValue) steps=\(stepCount) polyline=\(polylineCount)pts")
    }

    func logRerouteFailure(error: Error, attempt: Int) {
        guard level >= .stateChangesOnly else { return }
        logger.warning("[Reroute] ❌ attempt \(attempt) failed — \(String(describing: error))")
    }

    func logRerouteGiveUp(attempts: Int) {
        guard level >= .stateChangesOnly else { return }
        logger.warning("[Reroute] 🛑 giving up after \(attempts) attempts")
    }

    func logRerouteMisaligned(routeBearing: CLLocationDirection, userHeading: CLLocationDirection, delta: Double) {
        guard level >= .stateChangesOnly else { return }
        logger.warning("[Reroute] ⚠️ misaligned route — heading=\(String(format: "%.0f", userHeading))° routeBearing=\(String(format: "%.0f", routeBearing))° Δ=\(String(format: "%.0f", delta))°")
    }

    // MARK: - Raw Route (API 응답 원본)

    private let rawLogger = Logger(subsystem: "com.routin.navigation", category: "RawRoute")

    func logRawKakaoRoute(_ kakaoRoute: KakaoRouteResponse.KakaoRoute) {
        let dist = kakaoRoute.summary?.distance ?? 0
        let dur  = kakaoRoute.summary?.duration ?? 0
        rawLogger.debug("━━━ [RAW Kakao] dist=\(dist)m dur=\(dur)s resultCode=\(kakaoRoute.resultCode)")
        let sections = kakaoRoute.sections ?? []
        rawLogger.debug("  sections=\(sections.count) totalRoads=\(sections.reduce(0) { $0 + $1.roads.count }) totalGuides=\(sections.reduce(0) { $0 + $1.guides.count })")
        for (si, section) in sections.enumerated() {
            let vertexCount = section.roads.reduce(0) { $0 + $1.vertexes.count / 2 }
            rawLogger.debug("  section[\(si)] dist=\(section.distance)m dur=\(section.duration)s vertices=\(vertexCount)pts guides=\(section.guides.count)")
            for (gi, guide) in section.guides.enumerated() {
                rawLogger.debug("    guide[\(gi)] type=\(guide.type) dist=\(guide.distance)m dur=\(guide.duration)s name='\(guide.name)' guidance='\(guide.guidance)' xy=(\(String(format: "%.6f", guide.y)),\(String(format: "%.6f", guide.x)))")
            }
        }
        rawLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    func logRawAppleRoute(_ mkRoute: MKRoute) {
        rawLogger.debug("━━━ [RAW Apple] name='\(mkRoute.name)' dist=\(String(format: "%.0f", mkRoute.distance))m time=\(Int(mkRoute.expectedTravelTime))s")
        rawLogger.debug("  transportType=\(mkRoute.transportType.rawValue) hasHighways=\(mkRoute.hasHighways) hasTolls=\(mkRoute.hasTolls)")
        rawLogger.debug("  polylinePts=\(mkRoute.polyline.pointCount) steps=\(mkRoute.steps.count)")
        if !mkRoute.advisoryNotices.isEmpty {
            rawLogger.debug("  advisoryNotices=\(mkRoute.advisoryNotices.joined(separator: " | "))")
        }
        for (i, step) in mkRoute.steps.enumerated() {
            let notice = step.notice.map { " notice='\($0)'" } ?? ""
            rawLogger.debug("  step[\(i)] dist=\(String(format: "%.0f", step.distance))m polylinePts=\(step.polyline.pointCount) transportType=\(step.transportType.rawValue)\(notice)")
            rawLogger.debug("    instructions='\(step.instructions)'")
        }
        rawLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
