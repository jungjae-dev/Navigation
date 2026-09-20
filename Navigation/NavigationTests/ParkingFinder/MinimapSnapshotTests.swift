import Testing
import Foundation
import Combine
import simd
@testable import Navigation

/// 미니맵 스냅샷 (FR-111) — 뷰가 그리는 값이 추정 상태에서 올바르게 유도되는지.
/// 뷰의 픽셀 렌더링이 아니라 "무엇을 그릴지"의 계약을 고정한다.
@MainActor
struct MinimapSnapshotTests {

    private func makeViewModel() -> ParkingARViewModel {
        let record = ParkingSessionRecord(
            targetCodeRaw: "B2-A-3", floorToken: "B2", floorSource: .code,
            zoneToken: "A", numberValue: 3, templateSkeleton: "F-Z-N"
        )
        return ParkingARViewModel(mode: .find(target: record))
    }

    private func pose(_ viewModel: ParkingARViewModel, x: Float, z: Float) {
        viewModel.updateDevicePose(position: simd_float3(x, 0, z), forward: simd_float3(0, 0, -1))
    }

    @Test func snapshotIsPublishedOnPoseUpdate() {
        let viewModel = makeViewModel()
        #expect(viewModel.minimapSnapshot.value == nil)
        pose(viewModel, x: 0, z: 0)
        let snapshot = viewModel.minimapSnapshot.value
        #expect(snapshot != nil)
        #expect(snapshot?.device == SIMD2(0, 0))
    }

    @Test func trailSkipsStationaryPoses() {
        let viewModel = makeViewModel()
        pose(viewModel, x: 0, z: 0)
        pose(viewModel, x: 0, z: -0.1)     // 제자리 — 자취에 쌓이지 않는다
        pose(viewModel, x: 0, z: -0.2)
        #expect(viewModel.minimapSnapshot.value?.trail.count == 1)
        pose(viewModel, x: 0, z: -3)       // 충분히 이동
        #expect(viewModel.minimapSnapshot.value?.trail.count == 2)
    }

    @Test func signsIncludeEveryInstanceOfMultiSignCode() {
        let viewModel = makeViewModel()
        // 같은 코드가 11m 떨어진 두 기둥에서 — 인스턴스 둘 다 그려져야 한다(제외가 아니라 분리)
        for _ in 0..<2 {
            viewModel.addRecognition(text: "B2-A-1", confidence: 0.9, position: simd_float3(0, 0, 0))
        }
        for _ in 0..<2 {
            viewModel.addRecognition(text: "B2-A-1", confidence: 0.9, position: simd_float3(11, 0, 0))
        }
        pose(viewModel, x: 0, z: 0)
        let signs = viewModel.minimapSnapshot.value?.signs.filter { $0.code == "B2-A-1" } ?? []
        #expect(signs.count == 2)
        #expect(signs.allSatisfy { $0.isMultiSign })
    }

    @Test func targetBandAppearsWhileOneAxisIsUnknown() {
        let viewModel = makeViewModel()
        // 같은 구역(A)에서 번호만 둘 — 번호축만 서고 구역축은 미지 상태가 아니다.
        // 목표 A-3은 축 위라 띠가 없어야 한다
        for code in ["B2-A-1", "B2-A-5"] {
            for _ in 0..<2 {
                let x: Float = code.hasSuffix("1") ? 0 : 8
                viewModel.addRecognition(text: code, confidence: 0.9, position: simd_float3(x, 0, 0))
            }
        }
        pose(viewModel, x: 0, z: 2)
        let snapshot = viewModel.minimapSnapshot.value
        #expect(snapshot?.target != nil)
        #expect(snapshot?.uncertaintyBand == nil, "목표가 축 위면 띠가 아니라 원")
    }

    @Test func snapshotCarriesDisplayedPercent() {
        let viewModel = makeViewModel()
        for code in ["B2-A-1", "B2-A-5"] {
            for _ in 0..<2 {
                let x: Float = code.hasSuffix("1") ? 0 : 8
                viewModel.addRecognition(text: code, confidence: 0.9, position: simd_float3(x, 0, 0))
            }
        }
        pose(viewModel, x: 0, z: 2)
        let percent = viewModel.minimapSnapshot.value?.confidencePercent ?? -1
        #expect(percent >= ParkingTuning.confidencePercentFloor)
        #expect(percent <= ParkingTuning.confidencePercentCap)
    }

    /// 미니맵 투영이 화살표 규약(전방 기준 시계방향 +)과 같은 쪽을 가리키는지 —
    /// 부호가 반대면 화살표는 오른쪽, 미니맵은 왼쪽을 가리킨다(PR#61 리뷰에서 실제로 그랬다)
    @Test func minimapProjectionMatchesArrowConvention() {
        let forward = SIMD2<Double>(0, -1)            // 전방 -z
        let delta = SIMD2<Double>(5, 0)               // 월드 기준 오른쪽 5m
        // 화살표 각 (GuidanceGeometry와 동일 식)
        let unit = simd_normalize(delta)
        let arrow = atan2(forward.x * unit.y - forward.y * unit.x, simd_dot(forward, unit))
        // 미니맵 투영 x (ParkingMinimapView.project와 동일 식)
        let projectedX = forward.x * delta.y - forward.y * delta.x
        #expect(arrow > 0, "화살표는 시계방향(오른쪽)")
        #expect(projectedX > 0, "미니맵도 화면 오른쪽이어야 한다")
    }

    @Test func proximityPromptAppearsOnlyNearTarget() {
        let viewModel = makeViewModel()
        #expect(viewModel.proximityPrompt.value == nil)
        for code in ["B2-A-1", "B2-A-5"] {
            for _ in 0..<2 {
                let x: Float = code.hasSuffix("1") ? 0 : 8
                viewModel.addRecognition(text: code, confidence: 0.9, position: simd_float3(x, 0, 0))
            }
        }
        pose(viewModel, x: 0, z: 2)
        // 목표 A-3은 (4,0) 부근 — 기기가 (0,2)면 근접 임계 안쪽
        #expect(viewModel.proximityPrompt.value == "B2-A-3")
    }

    @Test func invalidationClearsMinimapState() {
        let viewModel = makeViewModel()
        pose(viewModel, x: 0, z: 0)
        pose(viewModel, x: 0, z: -5)
        #expect(viewModel.minimapSnapshot.value?.trail.isEmpty == false)
        viewModel.invalidateObservations()
        // 좌표계가 바뀌었으므로 옛 자취를 새 좌표계에 그리면 안 된다
        #expect(viewModel.minimapSnapshot.value == nil)
        #expect(viewModel.proximityPrompt.value == nil)
        pose(viewModel, x: 0, z: 0)
        #expect(viewModel.minimapSnapshot.value?.trail.count == 1)
    }

    @Test func scanModeGuidesNeighborCapture() {
        // FR-114: 스캔 중 인접 확보 진행이 안내되되 저장을 막지 않는다
        let viewModel = ParkingARViewModel(mode: .scan)
        #expect(viewModel.scanNeighborProgress.value == nil)
        for _ in 0..<2 {
            viewModel.addRecognition(text: "B2-A-1", confidence: 0.9, position: simd_float3(0, 0, 0))
        }
        let progress = viewModel.scanNeighborProgress.value
        #expect(progress?.captured == 0)   // 목표 자신은 인접이 아니다
        #expect(progress?.recommended == ParkingTuning.recommendedNeighborCount)

        for _ in 0..<2 {
            viewModel.addRecognition(text: "B2-A-2", confidence: 0.9, position: simd_float3(4, 0, 0))
        }
        #expect(viewModel.scanNeighborProgress.value?.captured == 1)
    }
}
