import CoreLocation

/// 음성 안내 트리거 판정 (엔진 레이어 — TTS 재생은 Presentation에서)
/// 거리 밴드 기반으로 VoiceCommand를 생성하며, 중복 안내를 방지
final class VoiceEngine {

    // MARK: - Distance Band

    enum DistanceBand: Hashable {
        case preRoadName   // 1200m
        case preDistance    // 300m (일반) / 500m (고속)
        case imminent      // 120m (일반) / 200m (고속)
    }

    private struct AnnouncementKey: Hashable {
        let stepIndex: Int
        let band: DistanceBand
    }

    // MARK: - Configuration

    // 일반도로 (< 80km/h)
    private let normalBands: [(band: DistanceBand, distance: CLLocationDistance, tolerance: CLLocationDistance)] = [
        (.preRoadName, 1200, 200),
        (.preDistance,  300,  60),
        (.imminent,    120,  30),
    ]

    // 고속도로 (≥ 80km/h)
    private let highwayBands: [(band: DistanceBand, distance: CLLocationDistance, tolerance: CLLocationDistance)] = [
        (.preRoadName, 1200, 200),
        (.preDistance,  500, 100),
        (.imminent,    200,  50),
    ]

    // MARK: - Configuration

    private let minimumAnnouncementInterval: TimeInterval = 5  // 최소 안내 간격 (초)

    // MARK: - State

    private var announcedKeys = Set<AnnouncementKey>()
    private var hasAnnouncedInitial = false
    private var hasAnnouncedArrival = false
    private var hasAnnouncedReroute = false
    private var lastAnnouncementTime: Date = .distantPast
    private let provider: RouteProvider

    // MARK: - Init

    init(provider: RouteProvider) {
        self.provider = provider
    }

    // MARK: - Initial Announcement

    /// 주행 시작 시 1회 호출
    func checkInitial() -> VoiceCommand? {
        guard !hasAnnouncedInitial else { return nil }
        hasAnnouncedInitial = true
        lastAnnouncementTime = Date()
        return VoiceCommand(text: "경로 안내를 시작합니다", priority: .normal)
    }

    // MARK: - Check Trigger

    /// 매 틱마다 호출하여 음성 안내 트리거 판정
    func check(
        distanceToManeuver: CLLocationDistance,
        speed: CLLocationSpeed,
        stepIndex: Int,
        step: RouteStep
    ) -> VoiceCommand? {
        // 최소 안내 간격 체크
        guard Date().timeIntervalSince(lastAnnouncementTime) >= minimumAnnouncementInterval else {
            return nil
        }

        let isHighway = speed * 3.6 >= 80  // km/h
        let bands = isHighway ? highwayBands : normalBands

        for (band, triggerDistance, tolerance) in bands {
            let key = AnnouncementKey(stepIndex: stepIndex, band: band)

            // 이미 안내한 밴드는 스킵
            guard !announcedKeys.contains(key) else { continue }

            // 거리 밴드 판정: triggerDistance 근처에 있는지 (tolerance 범위)
            // 짧은 스텝 처리: distanceToManeuver가 triggerDistance보다 작으면 즉시 안내
            let inRange = distanceToManeuver <= triggerDistance + tolerance
                       && distanceToManeuver >= triggerDistance - tolerance

            let alreadyPastButFirstChance = distanceToManeuver < triggerDistance - tolerance

            if inRange || alreadyPastButFirstChance {
                // 더 가까운 밴드가 이미 지나갔으면 그 밴드로 안내
                let effectiveBand = findEffectiveBand(
                    distance: distanceToManeuver,
                    bands: bands,
                    stepIndex: stepIndex
                )

                guard let (selectedBand, _) = effectiveBand else { continue }
                let selectedKey = AnnouncementKey(stepIndex: stepIndex, band: selectedBand)
                guard !announcedKeys.contains(selectedKey) else { continue }

                announcedKeys.insert(selectedKey)

                let text = buildText(
                    band: selectedBand,
                    distance: distanceToManeuver,
                    step: step
                )
                lastAnnouncementTime = Date()
                return VoiceCommand(text: text, priority: .normal)
            }
        }

        return nil
    }

    // MARK: - State Change

    /// 상태 전이 시 음성 (도착/재탐색 — 각 1회)
    func checkStateChange(state: NavigationState) -> VoiceCommand? {
        switch state {
        case .arrived:
            guard !hasAnnouncedArrival else { return nil }
            hasAnnouncedArrival = true
            lastAnnouncementTime = Date()
            return VoiceCommand(text: "목적지에 도착했습니다", priority: .urgent)

        case .rerouting:
            guard !hasAnnouncedReroute else { return nil }
            hasAnnouncedReroute = true
            lastAnnouncementTime = Date()
            return VoiceCommand(text: "경로를 재탐색합니다", priority: .urgent)

        case .navigating:
            // rerouting → navigating 복귀 시 재탐색 플래그 리셋 (다음 이탈 시 다시 안내)
            hasAnnouncedReroute = false
            return nil

        default:
            return nil
        }
    }

    /// 스텝 전진 시 이전 스텝의 안내 기록 정리
    func onStepAdvanced(previousStepIndex: Int) {
        announcedKeys = announcedKeys.filter { $0.stepIndex != previousStepIndex }
    }

    /// 리셋 (재탐색 시)
    func reset() {
        announcedKeys.removeAll()
        hasAnnouncedInitial = false
        hasAnnouncedArrival = false
        hasAnnouncedReroute = false
        lastAnnouncementTime = .distantPast
    }

    // MARK: - Private: Find Effective Band

    /// 현재 거리에서 가장 적합한 (아직 안내 안 한) 밴드 찾기
    /// 순서 보장: 먼 밴드부터 탐색하여 가장 먼 미안내 밴드 선택
    /// 짧은 스텝에서는 이미 지나간 큰 밴드를 건너뛰고 가장 먼 유효 밴드로 안내
    private func findEffectiveBand(
        distance: CLLocationDistance,
        bands: [(band: DistanceBand, distance: CLLocationDistance, tolerance: CLLocationDistance)],
        stepIndex: Int
    ) -> (DistanceBand, CLLocationDistance)? {
        // 정방향 탐색: 먼 밴드(1200m)부터 → 가까운 밴드(120m) 순서
        for (band, triggerDist, _) in bands {
            let key = AnnouncementKey(stepIndex: stepIndex, band: band)
            if distance <= triggerDist && !announcedKeys.contains(key) {
                // 이 밴드보다 먼 밴드들은 이미 지나갔으므로 모두 마킹 (순서 역전 방지)
                for (prevBand, prevDist, _) in bands {
                    if prevDist > triggerDist {
                        announcedKeys.insert(AnnouncementKey(stepIndex: stepIndex, band: prevBand))
                    }
                }
                return (band, triggerDist)
            }
        }
        return nil
    }

    // MARK: - Private: Build Text

    /// 프로바이더별 음성 텍스트 생성
    private func buildText(
        band: DistanceBand,
        distance: CLLocationDistance,
        step: RouteStep
    ) -> String {
        switch provider {
        case .kakao:
            return buildKakaoText(band: band, distance: distance, step: step)
        case .apple:
            return buildAppleText(band: band, distance: distance, step: step)
        }
    }

    /// 카카오: turnType + roadName으로 조합
    private func buildKakaoText(band: DistanceBand, distance: CLLocationDistance, step: RouteStep) -> String {
        let direction = directionText(from: step.turnType)

        switch band {
        case .preRoadName:
            if let roadName = step.roadName {
                return "\(roadName) 방면 \(direction)입니다"
            }
            return "\(direction)입니다"

        case .preDistance:
            let distText = formatDistanceForVoice(distance)
            return "\(distText) 앞 \(direction)"

        case .imminent:
            return "전방 \(direction)"
        }
    }

    /// Apple: instructions 텍스트 그대로 활용
    private func buildAppleText(band: DistanceBand, distance: CLLocationDistance, step: RouteStep) -> String {
        let instruction = step.instructions

        switch band {
        case .preRoadName:
            return instruction

        case .preDistance:
            let distText = formatDistanceForVoice(distance)
            return "\(distText) 앞, \(instruction)"

        case .imminent:
            return "전방, \(instruction)"
        }
    }

    // MARK: - Private: Helpers

    /// TurnType → 한국어 방향 텍스트
    private func directionText(from turnType: TurnType) -> String {
        switch turnType {
        case .straight:     return "직진"
        case .leftTurn:     return "좌회전"
        case .rightTurn:    return "우회전"
        case .uTurn:        return "유턴"
        case .leftMerge:    return "왼쪽 합류"
        case .rightMerge:   return "오른쪽 합류"
        case .leftExit:     return "왼쪽 출구"
        case .rightExit:    return "오른쪽 출구"
        case .destination:  return "목적지 도착"
        case .unknown(let text):
            return text.isEmpty ? "직진" : text
        }
    }

    /// 거리를 음성용 텍스트로 변환
    private func formatDistanceForVoice(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            let km = meters / 1000.0
            if km == Double(Int(km)) {
                return "\(Int(km))킬로미터"
            }
            return String(format: "%.1f킬로미터", km)
        }
        // 100m 단위로 반올림
        let rounded = Int((meters / 100).rounded()) * 100
        return "\(max(rounded, 100))미터"
    }
}
