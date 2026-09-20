import Foundation
import simd

/// NDJSON 관측 로그 리플레이 (DR-003, 리플레이 계약).
/// codeObserved 스트림만으로 격자 추정을 재계산해 기록된 gridUpdated와 대조한다 —
/// 불일치 = 추정 로직 회귀. 관측 포함 규칙은 ParkingARViewModel.runEstimate와 동일해야 한다(계약).
struct ParkingEventReplayer {

    struct ReplayResult {
        var recomputedCount = 0
        var comparedCount = 0
        /// "라인 N: stage 기록=X 재계산=Y" 형식
        var mismatches: [String] = []
        var finalEstimate: GridEstimate?

        // MARK: - v3 지표 (spec 006 SC-101/103 게이트)
        /// 기기 포즈가 있어 화살표 판정이 가능했던 횟수
        var geometryEvaluated = 0
        /// 그중 FR-101 측방 각도 보장이 성립해 화살표를 표시했을 횟수
        var arrowShown = 0
        /// 화살표 표시 시 거리까지 보여줬을 횟수 (FR-106)
        var distanceShown = 0
        /// 화살표 표시 순간의 백분율 최대치 — 과신 회귀 감시 (SC-103)
        var maxPercentWhenShown = 0
        /// 화살표 표시 순간의 표시 거리 최대치(m)
        var maxDistanceWhenShown = 0.0

        var isConsistent: Bool { mismatches.isEmpty }
        /// SC-101 화살표 가동률
        var arrowAvailability: Double {
            geometryEvaluated == 0 ? 0 : Double(arrowShown) / Double(geometryEvaluated)
        }
    }

    enum ReplayError: Error {
        case unreadable
        case missingSessionStart
    }

    static func replay(fileURL: URL) throws -> ReplayResult {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw ReplayError.unreadable
        }
        return try replay(ndjson: content)
    }

    static func replay(ndjson: String) throws -> ReplayResult {
        var estimator = GridEstimator()
        var observations: [String: (parsed: ParsedCode, position: simd_float3?, hits: Int, positionUpdatedAt: Double?, ambiguous: Bool)] = [:]
        var targetParsed: ParsedCode?
        var neighborRaws: Set<String> = []
        var sawSessionStart = false
        var lastRecomputed: GridEstimate?
        var result = ReplayResult()
        // VM 패리티: 화살표 표시 판정에는 기기 포즈가 필요하다 (FR-101)
        var devicePosition: SIMD2<Double>?
        var deviceForward: SIMD2<Double>?

        for (index, line) in ndjson.split(separator: "\n").enumerated() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = object["e"] as? String else { continue }

            switch event {
            case "sessionStart":
                sawSessionStart = true
                if let target = object["target"] as? [String: Any],
                   let raw = target["raw"] as? String {
                    targetParsed = PillarCodeParser.parse(raw)
                }
                // VM 패리티: 인접 목격 신뢰도 부스트(FR-013a) 재현용 (PR#49 리뷰 — 미파싱으로 confidence 경로 불일치)
                if let neighbors = object["neighbors"] as? [String] {
                    neighborRaws = Set(neighbors.map { PillarCodeParser.normalized($0) })
                }

            case "codeObserved":
                guard let raw = object["raw"] as? String,
                      let hit = object["hit"] as? Int,
                      let parsed = PillarCodeParser.parse(raw) else { continue }
                let eventTime = (object["t"] as? Double) ?? 0
                let position: simd_float3? = (object["pos"] as? [Double]).flatMap { pos in
                    pos.count == 3 ? simd_float3(Float(pos[0]), Float(pos[1]), Float(pos[2])) : nil
                }
                let existing = observations[raw]
                // VM.upsertObservation 패리티: 위치 점프 → 모호(다중 표지판) 플래그, 이후 좌표 동결
                var ambiguous = existing?.ambiguous ?? false
                var storedPosition = existing?.position
                var storedPositionAt = existing?.positionUpdatedAt
                if let position {
                    if let old = storedPosition, !ambiguous,
                       simd_length(position - old) > ParkingTuning.sameCodeJumpThreshold {
                        ambiguous = true
                    } else if !ambiguous {
                        storedPosition = position
                        storedPositionAt = eventTime
                    }
                }
                observations[raw] = (parsed, storedPosition, hit, storedPositionAt, ambiguous)

                // VM 패리티: 인접 목격 → 신뢰도 부스트, estimate 호출 이전에 (VM handleFindRecognition과 동일 순서)
                if neighborRaws.contains(parsed.raw) {
                    estimator.markNeighborSighted()
                }

                // VM.runEstimate와 동일한 포함 규칙:
                // 확정(hit≥2) + 위치 보유 + 격자 사용 가능 + 신선도 + 비모호 + 잘림 의심(진접두사) 제외
                let confirmedRaws = Set(
                    observations.values.filter { $0.hits >= ParkingTuning.confirmHits }.map(\.parsed.raw)
                )
                let gridObservations = observations.values
                    .filter { $0.hits >= ParkingTuning.confirmHits && !$0.ambiguous }
                    .filter { entry in
                        !confirmedRaws.contains { other in
                            other != entry.parsed.raw && other.hasPrefix(entry.parsed.raw)
                        }
                    }
                    .compactMap { entry -> GridObservation? in
                        guard let p = entry.position, entry.parsed.isGridUsable else { return nil }
                        return GridObservation(
                            codeRaw: entry.parsed.raw,
                            zoneIndex: entry.parsed.zoneIndex,
                            numberValue: entry.parsed.numberValue,
                            position: SIMD2(Double(p.x), Double(p.z)),
                            ageSeconds: entry.positionUpdatedAt.map { eventTime - $0 } ?? 0
                        )
                    }
                // VM 패리티: 위치 있는 관측이 0개여도 추정 실행 (→ searching 기록됨)
                lastRecomputed = estimator.estimate(
                    observations: gridObservations,
                    targetZoneIndex: targetParsed?.zoneIndex,
                    targetNumber: targetParsed?.numberValue
                )
                result.recomputedCount += 1

            case "gridUpdated":
                guard let recordedStage = object["stage"] as? String else { continue }
                result.comparedCount += 1
                let recomputedStage = lastRecomputed.map { String(describing: $0.stage) } ?? "nil"
                if recomputedStage != recordedStage {
                    result.mismatches.append(
                        "line \(index + 1): stage 기록=\(recordedStage) 재계산=\(recomputedStage)"
                    )
                }
                if let recordedTarget = object["targetEst"] as? [Double], recordedTarget.count == 2,
                   let recomputedTarget = lastRecomputed?.targetPosition {
                    let distance = simd_length(SIMD2(recordedTarget[0], recordedTarget[1]) - recomputedTarget)
                    if distance > 0.05 {
                        result.mismatches.append(
                            "line \(index + 1): targetEst 오차 \(String(format: "%.3f", distance))m"
                        )
                    }
                }
                // confidence·lever 비교 (PR#49 리뷰 — 260801 과신 버그 부류의 회귀를 잡기 위한 필수 비교)
                if let recordedConfidence = object["confidence"] as? Int,
                   let recomputed = lastRecomputed,
                   recomputed.confidence.rawValue != recordedConfidence {
                    result.mismatches.append(
                        "line \(index + 1): confidence 기록=\(recordedConfidence) 재계산=\(recomputed.confidence.rawValue)"
                    )
                }
                if let recordedLever = object["lever"] as? Double,
                   let recomputedLever = lastRecomputed?.extrapolationLever,
                   abs(recordedLever - recomputedLever) > 0.05 {
                    result.mismatches.append(
                        "line \(index + 1): lever 기록=\(String(format: "%.2f", recordedLever)) 재계산=\(String(format: "%.2f", recomputedLever))"
                    )
                }
                // v3 백분율 — 구 로그에는 없는 필드라 있을 때만 비교 (FR-116 패리티, 하위 호환)
                if let recordedPercent = object["conf%"] as? Int,
                   let recomputed = lastRecomputed,
                   recomputed.confidencePercent != recordedPercent {
                    result.mismatches.append(
                        "line \(index + 1): conf% 기록=\(recordedPercent) 재계산=\(recomputed.confidencePercent)"
                    )
                }

            case "devicePose":
                if let pos = object["pos"] as? [Double], pos.count == 3 {
                    devicePosition = SIMD2(pos[0], pos[2])
                }
                if let heading = object["heading"] as? [Double], heading.count == 2 {
                    let vector = SIMD2(heading[0], heading[1])
                    if simd_length(vector) > 1e-6 { deviceForward = simd_normalize(vector) }
                }
                // 포즈 갱신 시점마다 화살표 표시 여부를 재평가 — VM.updateDevicePose와 같은 주기 (PR#49 M5)
                if let estimate = lastRecomputed, let target = estimate.targetPosition,
                   let position = devicePosition, let forward = deviceForward {
                    let geometry = GuidanceGeometry.evaluate(
                        target: target, uncertainty: estimate.uncertainty,
                        devicePosition: position, deviceForward: forward,
                        observationSpan: estimate.observationSpan,
                        confidencePercent: estimate.confidencePercent
                    )
                    result.geometryEvaluated += 1
                    if geometry.isDirectionGuaranteed {
                        result.arrowShown += 1
                        result.maxPercentWhenShown = max(result.maxPercentWhenShown, estimate.confidencePercent)
                        result.maxDistanceWhenShown = max(result.maxDistanceWhenShown, geometry.distance)
                        if geometry.isDistanceDisplayable { result.distanceShown += 1 }
                    }
                }

            case "observationsInvalidated":
                // VM.invalidateObservations 패리티 — 중단 시점의 관측·추정 상태 리셋 (PR#49 리뷰 L8)
                observations.removeAll()
                estimator.reset()
                lastRecomputed = nil

            default:
                break
            }
        }

        guard sawSessionStart else { throw ReplayError.missingSessionStart }
        result.finalEstimate = lastRecomputed
        return result
    }
}
