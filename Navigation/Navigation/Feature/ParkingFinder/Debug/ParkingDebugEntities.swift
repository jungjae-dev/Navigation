import Foundation
import RealityKit
import simd
import UIKit

/// DR-001 공간 디버그 시각화 — 앵커 라벨·목표 마커·잔차선·고스트 격자점·이동 궤적.
/// 공간 오류는 공간에 그려야 보인다: 라벨이 기둥에 안 붙어 있으면 raycast 오류가 즉시 드러남.
final class ParkingDebugEntities {

    private weak var arView: ARView?
    private var codeAnchors: [String: AnchorEntity] = [:]
    private var targetAnchor: AnchorEntity?
    private var modelAnchor: AnchorEntity?   // 잔차선·고스트 격자점 (모델 갱신마다 재생성)
    private var trailAnchor = AnchorEntity(world: .zero)
    private var trailCount = 0

    init(arView: ARView) {
        self.arView = arView
        arView.scene.addAnchor(trailAnchor)
    }

    func removeAll() {
        codeAnchors.values.forEach { $0.removeFromParent() }
        codeAnchors = [:]
        targetAnchor?.removeFromParent()
        targetAnchor = nil
        modelAnchor?.removeFromParent()
        modelAnchor = nil
        trailAnchor.children.removeAll()
        trailCount = 0
    }

    // MARK: - 코드 앵커 라벨 (신뢰도 색: 확정 흰색 / 1회 노랑)

    func syncCodeLabels(_ observations: [String: ParkingARViewModel.Observation]) {
        guard let arView else { return }
        for (code, observation) in observations {
            guard let position = observation.position else { continue }
            let confirmed = observation.hits >= ParkingTuning.confirmHits

            if let existing = codeAnchors[code] {
                existing.position = position
                continue
            }
            let anchor = AnchorEntity(world: position)
            anchor.addChild(Self.textEntity(code, color: confirmed ? .white : .systemYellow))
            arView.scene.addAnchor(anchor)
            codeAnchors[code] = anchor
        }
    }

    // MARK: - 목표 예측 마커 (가상 핀)

    func updateTarget(_ xz: SIMD2<Double>?, referenceY: Float) {
        targetAnchor?.removeFromParent()
        targetAnchor = nil
        guard let arView, let xz else { return }

        let anchor = AnchorEntity(world: simd_float3(Float(xz.x), referenceY, Float(xz.y)))
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.15),
            materials: [UnlitMaterial(color: UIColor.systemIndigo.withAlphaComponent(0.85))]
        )
        anchor.addChild(sphere)
        anchor.addChild(Self.textEntity("◎ 목표", color: .systemIndigo, yOffset: 0.25))
        arView.scene.addAnchor(anchor)
        targetAnchor = anchor
    }

    // MARK: - 잔차선 + 고스트 격자점 (예측 vs 관측 — 강등 트리거 시각 확인)

    func updateModel(estimate: GridEstimate, observations: [String: ParkingARViewModel.Observation]) {
        modelAnchor?.removeFromParent()
        modelAnchor = nil
        guard let arView, estimate.origin != nil else { return }

        let anchor = AnchorEntity(world: .zero)
        for observation in observations.values {
            guard let actual = observation.position,
                  observation.hits >= ParkingTuning.confirmHits,
                  let predicted = estimate.predictedPosition(
                    zoneIndex: observation.parsed.zoneIndex,
                    number: observation.parsed.numberValue
                  ) else { continue }

            let predicted3 = simd_float3(Float(predicted.x), actual.y, Float(predicted.y))
            // 고스트 격자점 (예측 위치)
            let ghost = ModelEntity(
                mesh: .generateSphere(radius: 0.05),
                materials: [UnlitMaterial(color: UIColor.systemTeal.withAlphaComponent(0.7))]
            )
            ghost.position = predicted3
            anchor.addChild(ghost)
            // 잔차선 (예측 → 실제) — 길수록 모델 모순
            if let line = Self.lineEntity(from: predicted3, to: actual, color: .systemRed) {
                anchor.addChild(line)
            }
        }
        arView.scene.addAnchor(anchor)
        modelAnchor = anchor
    }

    // MARK: - 이동 궤적

    func addTrailPoint(_ position: simd_float3) {
        guard trailCount < 300 else { return }   // 상한 — 메모리·렌더 보호
        trailCount += 1
        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [UnlitMaterial(color: UIColor.systemGray.withAlphaComponent(0.6))]
        )
        dot.position = simd_float3(position.x, position.y - 0.3, position.z)
        trailAnchor.addChild(dot)
    }

    // MARK: - Helpers

    private static func textEntity(_ text: String, color: UIColor, yOffset: Float = 0.1) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.005,
            font: .monospacedSystemFont(ofSize: 0.12, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        entity.position.y = yOffset
        return entity
    }

    private static func lineEntity(from: simd_float3, to: simd_float3, color: UIColor) -> ModelEntity? {
        let vector = to - from
        let length = simd_length(vector)
        guard length > 0.01 else { return nil }

        let line = ModelEntity(
            mesh: .generateBox(size: simd_float3(0.01, 0.01, length)),
            materials: [UnlitMaterial(color: color.withAlphaComponent(0.8))]
        )
        line.position = (from + to) / 2
        line.orientation = simd_quatf(from: simd_float3(0, 0, 1), to: simd_normalize(vector))
        return line
    }
}
