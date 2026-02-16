import Foundation
import MapKit

enum GuidanceTextBuilder {

    // MARK: - Guidance Types

    enum GuidanceType {
        case approaching(distance: Int, instruction: String)
        case imminent(instruction: String)
        case departed
        case rerouting
        case rerouted
        case arrived
        case straightAhead(distance: Int)
        case parkingApproach
    }

    // MARK: - Text Generation

    static func buildText(for type: GuidanceType) -> String {
        switch type {
        case .approaching(let distance, let instruction):
            let distText = formatDistanceForVoice(Double(distance))
            let cleanInstruction = cleanInstruction(instruction)
            return "\(distText) 앞에서 \(cleanInstruction)"

        case .imminent(let instruction):
            let cleanInstruction = cleanInstruction(instruction)
            return "잠시 후 \(cleanInstruction)"

        case .departed:
            return "경로를 이탈했습니다"

        case .rerouting:
            return "새로운 경로를 탐색합니다"

        case .rerouted:
            return "새로운 경로로 안내합니다"

        case .arrived:
            return "목적지에 도착했습니다"

        case .straightAhead(let distance):
            let distText = formatDistanceForVoice(Double(distance))
            return "\(distText) 직진하세요"

        case .parkingApproach:
            return "목적지 부근에 도착합니다. 주차 안내를 시작합니다."
        }
    }

    // MARK: - Distance Formatting for Voice

    static func formatDistanceForVoice(_ meters: CLLocationDistance) -> String {
        if meters < 100 {
            return "\(Int(meters))미터"
        } else if meters < 1000 {
            let rounded = Int(meters / 100) * 100
            return "\(rounded)미터"
        } else {
            let km = meters / 1000.0
            if km == Double(Int(km)) {
                return "\(Int(km))킬로미터"
            } else {
                return String(format: "%.1f킬로미터", km)
            }
        }
    }

    // MARK: - Instruction Processing

    /// Build instruction text from MKRoute.Step
    static func buildInstructionFromStep(_ step: MKRoute.Step) -> String {
        let instruction = step.instructions
        guard !instruction.isEmpty else {
            return "직진하세요"
        }
        return cleanInstruction(instruction)
    }

    // MARK: - Maneuver Icon Mapping

    /// Map instruction text to SF Symbol name
    static func iconNameForInstruction(_ instruction: String) -> String {
        let lower = instruction.lowercased()

        if lower.contains("우회전") || lower.contains("right") {
            return "arrow.turn.up.right"
        } else if lower.contains("좌회전") || lower.contains("left") {
            return "arrow.turn.up.left"
        } else if lower.contains("유턴") || lower.contains("u-turn") || lower.contains("u turn") {
            return "arrow.uturn.left"
        } else if lower.contains("합류") || lower.contains("merge") {
            return "arrow.merge"
        } else if lower.contains("출구") || lower.contains("exit") || lower.contains("램프") || lower.contains("ramp") {
            return "arrow.up.right"
        } else if lower.contains("도착") || lower.contains("destination") {
            return "flag.fill"
        } else {
            return "arrow.up"
        }
    }

    // MARK: - Private

    /// Ensure instruction ends with imperative form for Korean TTS
    private static func cleanInstruction(_ instruction: String) -> String {
        var cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove trailing period
        if cleaned.hasSuffix(".") {
            cleaned = String(cleaned.dropLast())
        }

        // Add "하세요" suffix if instruction doesn't already end with a Korean imperative
        if !cleaned.hasSuffix("세요") && !cleaned.hasSuffix("시오") && !cleaned.hasSuffix("니다") {
            cleaned += "하세요"
        }

        return cleaned
    }
}
