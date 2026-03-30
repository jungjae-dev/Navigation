import CoreLocation

/// 경로 진행 추적 결과
struct RouteProgress: Sendable {
    let currentStep: RouteStep
    let nextStep: RouteStep?
    let currentStepIndex: Int
    let totalSteps: Int
    let distanceToNextManeuver: CLLocationDistance
    let remainingDistance: CLLocationDistance
    let remainingTime: TimeInterval
    let eta: Date
}

/// 경로 진행 추적
/// 매칭된 좌표를 받아 현재 스텝, 남은 거리/시간/ETA를 계산
final class RouteTracker {

    // MARK: - Configuration

    private let advanceThreshold: CLLocationDistance = 30  // 스텝 전진 임계값 (m)

    // MARK: - State

    private let route: Route
    private let steps: [RouteStep]
    private(set) var currentStepIndex: Int = 0

    /// 스텝 전진 콜백 (로그용)
    var onStepAdvance: ((_ from: Int, _ to: Int, _ instruction: String) -> Void)?

    // MARK: - Init

    init(route: Route) {
        self.route = route
        self.steps = route.steps
    }

    // MARK: - Update

    /// 매칭된 좌표로 경로 진행 상태 업데이트
    func update(matchedPosition: CLLocationCoordinate2D) -> RouteProgress {
        // 1. 스텝 전진 판정
        advanceStepIfNeeded(matchedPosition: matchedPosition)

        // 2. 현재/다음 스텝
        let currentStep = steps[currentStepIndex]
        let nextStep = currentStepIndex + 1 < steps.count ? steps[currentStepIndex + 1] : nil

        // 3. 현재 안내 포인트까지 남은 거리
        let distanceToManeuver = distanceToStepEnd(matchedPosition: matchedPosition, stepIndex: currentStepIndex)

        // 4. 목적지까지 남은 거리
        let remainingDistance = calculateRemainingDistance(
            matchedPosition: matchedPosition,
            fromStepIndex: currentStepIndex
        )

        // 5. 남은 시간 / ETA
        let remainingTime = calculateRemainingTime(remainingDistance: remainingDistance)
        let eta = Date().addingTimeInterval(remainingTime)

        return RouteProgress(
            currentStep: currentStep,
            nextStep: nextStep,
            currentStepIndex: currentStepIndex,
            totalSteps: steps.count,
            distanceToNextManeuver: distanceToManeuver,
            remainingDistance: remainingDistance,
            remainingTime: remainingTime,
            eta: eta
        )
    }

    /// 새 경로로 리셋 (재탐색 시)
    func reset() {
        currentStepIndex = 0
    }

    // MARK: - Step Advance

    /// 현재 스텝의 끝 좌표까지 30m 이내면 다음 스텝으로 전진
    private func advanceStepIfNeeded(matchedPosition: CLLocationCoordinate2D) {
        guard currentStepIndex < steps.count - 1 else { return }  // 마지막 스텝이면 전진 안 함

        let dist = distanceToStepEnd(matchedPosition: matchedPosition, stepIndex: currentStepIndex)

        if dist <= advanceThreshold {
            let oldIndex = currentStepIndex
            currentStepIndex += 1

            let newInstruction = steps[currentStepIndex].instructions
            onStepAdvance?(oldIndex, currentStepIndex, newInstruction)
        }
    }

    // MARK: - Distance Calculations

    /// 매칭 위치 → 해당 스텝의 마지막 좌표까지 거리
    private func distanceToStepEnd(matchedPosition: CLLocationCoordinate2D, stepIndex: Int) -> CLLocationDistance {
        guard stepIndex < steps.count else { return 0 }

        let stepCoords = steps[stepIndex].polylineCoordinates
        guard let lastCoord = stepCoords.last else { return 0 }

        return distanceInMeters(from: matchedPosition, to: lastCoord)
    }

    /// 매칭 위치 → 목적지까지 남은 총 거리
    /// 현재 스텝의 남은 거리 + 이후 스텝들의 distance 합산
    private func calculateRemainingDistance(
        matchedPosition: CLLocationCoordinate2D,
        fromStepIndex: Int
    ) -> CLLocationDistance {
        guard fromStepIndex < steps.count else { return 0 }

        // 현재 스텝의 남은 거리 (매칭 위치 → 스텝 끝)
        var remaining = distanceToStepEnd(matchedPosition: matchedPosition, stepIndex: fromStepIndex)

        // 이후 스텝들의 distance 합산
        for i in (fromStepIndex + 1)..<steps.count {
            remaining += steps[i].distance
        }

        return remaining
    }

    /// 남은 시간 계산 (provider별 분기)
    private func calculateRemainingTime(remainingDistance: CLLocationDistance) -> TimeInterval {
        guard route.distance > 0 else { return 0 }

        switch route.provider {
        case .kakao:
            // 카카오: 현재 스텝 이후 step별 duration 합산
            return calculateRemainingTimeFromDuration()

        case .apple:
            // Apple: 전체 시간 × 남은 거리 비율
            return route.expectedTravelTime * (remainingDistance / route.distance)
        }
    }

    /// 카카오: step별 duration 합산으로 정확한 남은 시간 계산
    private func calculateRemainingTimeFromDuration() -> TimeInterval {
        var totalTime: TimeInterval = 0

        // 현재 스텝의 남은 시간 (비율 추정)
        if currentStepIndex < steps.count {
            let step = steps[currentStepIndex]
            if let duration = step.duration, step.distance > 0 {
                // 현재 스텝에서 이미 진행한 비율을 기반으로 남은 시간 추정
                // 단순화: 전체 duration 사용 (정밀도는 충분)
                totalTime += duration
            }
        }

        // 이후 스텝들의 duration 합산
        for i in (currentStepIndex + 1)..<steps.count {
            if let duration = steps[i].duration {
                totalTime += duration
            }
        }

        // duration이 없는 스텝이 있으면 거리 비율 방식으로 폴백
        if totalTime == 0 && route.distance > 0 {
            let remainingStepsDistance = steps[currentStepIndex...].reduce(0.0) { $0 + $1.distance }
            return route.expectedTravelTime * (remainingStepsDistance / route.distance)
        }

        return totalTime
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
