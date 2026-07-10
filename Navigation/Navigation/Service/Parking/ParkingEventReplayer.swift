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

        var isConsistent: Bool { mismatches.isEmpty }
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
        var observations: [String: (parsed: ParsedCode, position: simd_float3?, hits: Int)] = [:]
        var targetParsed: ParsedCode?
        var sawSessionStart = false
        var lastRecomputed: GridEstimate?
        var result = ReplayResult()

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

            case "codeObserved":
                guard let raw = object["raw"] as? String,
                      let hit = object["hit"] as? Int,
                      let parsed = PillarCodeParser.parse(raw) else { continue }
                let position: simd_float3? = (object["pos"] as? [Double]).flatMap { pos in
                    pos.count == 3 ? simd_float3(Float(pos[0]), Float(pos[1]), Float(pos[2])) : nil
                }
                let existing = observations[raw]
                observations[raw] = (parsed, position ?? existing?.position, hit)

                // VM.runEstimate와 동일한 포함 규칙: 확정(hit≥2) + 위치 보유 + 격자 사용 가능
                let gridObservations = observations.values
                    .filter { $0.hits >= ParkingTuning.confirmHits }
                    .compactMap { entry -> GridObservation? in
                        guard let p = entry.position, entry.parsed.isGridUsable else { return nil }
                        return GridObservation(
                            codeRaw: entry.parsed.raw,
                            zoneIndex: entry.parsed.zoneIndex,
                            numberValue: entry.parsed.numberValue,
                            position: SIMD2(Double(p.x), Double(p.z))
                        )
                    }
                guard gridObservations.count >= 1 else { continue }
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

            default:
                break
            }
        }

        guard sawSessionStart else { throw ReplayError.missingSessionStart }
        result.finalEstimate = lastRecomputed
        return result
    }
}
