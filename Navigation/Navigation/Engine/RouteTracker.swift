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
/// 매칭된 좌표 + segmentIndex를 받아 현재 스텝, 남은 거리/시간/ETA를 계산
/// 스텝 전진: TMAP 방식 — segmentIndex가 Step 끝 인덱스를 지나가면 전진
final class RouteTracker {

    // MARK: - State

    private let route: Route
    private let steps: [RouteStep]
    private(set) var currentStepIndex: Int = 0

    /// 각 Step의 끝 좌표에 해당하는 전체 폴리라인 인덱스
    private let stepEndSegmentIndices: [Int]

    /// 스텝 전진 콜백 (로그용)
    var onStepAdvance: ((_ from: Int, _ to: Int, _ instruction: String) -> Void)?

    // MARK: - Init

    init(route: Route) {
        self.route = route
        self.steps = route.steps
        self.stepEndSegmentIndices = Self.buildStepEndIndices(
            steps: route.steps,
            polyline: route.polylineCoordinates
        )

        // 디버그: stepEndSegmentIndices 로그
        for (i, endIdx) in stepEndSegmentIndices.enumerated() {
            let stepCoordCount = route.steps[i].polylineCoordinates.count
            let lastCoord = route.steps[i].polylineCoordinates.last
            let lastStr = lastCoord.map { "(\(String(format: "%.6f", $0.latitude)),\(String(format: "%.6f", $0.longitude)))" } ?? "nil"
            print("[RouteTracker] Step \(i) endSegIdx=\(endIdx) polyline=\(stepCoordCount)pts last=\(lastStr) instruction=\(route.steps[i].instructions)")
        }
        print("[RouteTracker] Total polyline=\(route.polylineCoordinates.count)pts")

        // 출발지 step 스킵 (카카오 type=100: polyline=1pts, 안내가 아닌 시작점 마커)
        skipDepartureStep()
    }

    // MARK: - Update

    /// 매칭된 좌표 + segmentIndex로 경로 진행 상태 업데이트
    func update(matchedPosition: CLLocationCoordinate2D, segmentIndex: Int) -> RouteProgress {
        // 1. 스텝 전진 판정 (segmentIndex 기반)
        advanceStepIfNeeded(segmentIndex: segmentIndex)

        // 2. 현재/다음 스텝
        let currentStep = steps[currentStepIndex]
        let nextStep = currentStepIndex + 1 < steps.count ? steps[currentStepIndex + 1] : nil

        // 3. 현재 안내 포인트까지 남은 거리
        let distanceToManeuver = distanceToStepEnd(
            matchedPosition: matchedPosition,
            stepIndex: currentStepIndex
        )

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

    /// 하위 호환: segmentIndex 없이 호출 (기존 인터페이스)
    func update(matchedPosition: CLLocationCoordinate2D) -> RouteProgress {
        // segmentIndex를 좌표에서 추정
        let estimatedIndex = estimateSegmentIndex(for: matchedPosition)
        return update(matchedPosition: matchedPosition, segmentIndex: estimatedIndex)
    }

    /// 리셋 (재탐색 시)
    func reset() {
        currentStepIndex = 0
        skipDepartureStep()
    }

    // MARK: - Step Advance (segmentIndex 기반 — TMAP 방식)

    /// 매칭된 segmentIndex가 현재 Step의 끝 인덱스를 지나갔으면 전진
    private func advanceStepIfNeeded(segmentIndex: Int) {
        while currentStepIndex < steps.count - 1 {
            let stepEndIndex = stepEndSegmentIndices[currentStepIndex]
            if segmentIndex >= stepEndIndex {
                let oldIndex = currentStepIndex
                currentStepIndex += 1
                let newInstruction = steps[currentStepIndex].instructions
                onStepAdvance?(oldIndex, currentStepIndex, newInstruction)
            } else {
                break
            }
        }
    }

    // MARK: - Departure Skip

    /// 출발지 step 스킵 (polyline=1pts인 시작점 마커)
    private func skipDepartureStep() {
        if currentStepIndex < steps.count - 1,
           steps[currentStepIndex].polylineCoordinates.count <= 1 {
            currentStepIndex += 1
        }
    }

    // MARK: - Step End Index Mapping

    /// 각 Step의 마지막 좌표를 전체 폴리라인에서 찾아 인덱스 배열 생성
    private static func buildStepEndIndices(
        steps: [RouteStep],
        polyline: [CLLocationCoordinate2D]
    ) -> [Int] {
        guard !polyline.isEmpty else {
            return Array(repeating: 0, count: steps.count)
        }

        var indices: [Int] = []
        var searchStart = 0

        for step in steps {
            guard let lastCoord = step.polylineCoordinates.last else {
                indices.append(searchStart)
                continue
            }

            // 순방향 탐색: searchStart 이후에서 가장 가까운 점
            var bestIndex = searchStart
            var bestDistance: Double = .infinity

            for i in searchStart..<polyline.count {
                let dist = simpleDistance(polyline[i], lastCoord)
                if dist < bestDistance {
                    bestDistance = dist
                    bestIndex = i
                }
                // 정확히 일치 (좌표 동일) → 즉시 종료
                if dist < 1e-12 { break }
            }

            indices.append(bestIndex)
            // 다음 step은 이 점 이후부터 탐색 (같은 점에서 시작하지 않도록 +1)
            searchStart = bestIndex
        }

        return indices
    }

    /// 간이 좌표 거리 (도 단위 차이, 인덱스 매핑용)
    private static func simpleDistance(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let dlat = a.latitude - b.latitude
        let dlon = a.longitude - b.longitude
        return dlat * dlat + dlon * dlon
    }

    // MARK: - Segment Index Estimation

    /// 좌표에서 segmentIndex 추정 (하위 호환용)
    private func estimateSegmentIndex(for position: CLLocationCoordinate2D) -> Int {
        let polyline = route.polylineCoordinates
        guard polyline.count >= 2 else { return 0 }

        var bestIndex = 0
        var bestDistance = Self.simpleDistance(polyline[0], position)

        for i in 1..<polyline.count {
            let dist = Self.simpleDistance(polyline[i], position)
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = i
            }
        }

        return max(0, bestIndex - 1)  // segment index = point index - 1
    }

    // MARK: - Distance Calculations

    /// 매칭 위치 → 해당 스텝의 마지막 좌표까지 거리
    private func distanceToStepEnd(
        matchedPosition: CLLocationCoordinate2D,
        stepIndex: Int
    ) -> CLLocationDistance {
        guard stepIndex < steps.count else { return 0 }

        let stepCoords = steps[stepIndex].polylineCoordinates
        guard let lastCoord = stepCoords.last else { return 0 }

        return distanceInMeters(from: matchedPosition, to: lastCoord)
    }

    /// 매칭 위치 → 목적지까지 남은 총 거리
    private func calculateRemainingDistance(
        matchedPosition: CLLocationCoordinate2D,
        fromStepIndex: Int
    ) -> CLLocationDistance {
        guard fromStepIndex < steps.count else { return 0 }

        var remaining = distanceToStepEnd(matchedPosition: matchedPosition, stepIndex: fromStepIndex)

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
            return calculateRemainingTimeFromDuration()
        case .apple:
            return route.expectedTravelTime * (remainingDistance / route.distance)
        }
    }

    /// 카카오: step별 duration 합산
    private func calculateRemainingTimeFromDuration() -> TimeInterval {
        var totalTime: TimeInterval = 0

        if currentStepIndex < steps.count {
            if let duration = steps[currentStepIndex].duration {
                totalTime += duration
            }
        }

        for i in (currentStepIndex + 1)..<steps.count {
            if let duration = steps[i].duration {
                totalTime += duration
            }
        }

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
