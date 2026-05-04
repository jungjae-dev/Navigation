import Testing
import CoreLocation
@testable import Navigation

struct LocationInterpolatorTests {

    static let A = CLLocationCoordinate2D(latitude: 37.500, longitude: 127.000)  // 경로 위 위치
    static let B = CLLocationCoordinate2D(latitude: 37.501, longitude: 127.001)  // 맵매칭 위치
    static let C = CLLocationCoordinate2D(latitude: 37.510, longitude: 127.010)  // 경로 밖 raw GPS

    // MARK: - 기본 동작

    @Test func initialState_returnsTargetBeforeFirstSet() {
        let interp = LocationInterpolator()
        let result = interp.interpolate()
        // isInitialized = false → target의 기본값 (0,0) 반환
        #expect(result.coordinate.latitude == 0)
        #expect(result.coordinate.longitude == 0)
    }

    @Test func resetTo_setsPositionImmediately() {
        let interp = LocationInterpolator()
        interp.resetTo(Self.A, 90)
        let result = interp.interpolate()
        #expect(abs(result.coordinate.latitude - Self.A.latitude) < 1e-9)
        #expect(abs(result.coordinate.longitude - Self.A.longitude) < 1e-9)
        #expect(abs(result.heading - 90) < 1e-9)
    }

    @Test func setTarget_firstCall_startsFromResetPosition() {
        let interp = LocationInterpolator()
        interp.resetTo(Self.A, 0)
        interp.setTarget(Self.B, heading: 45)

        // t≈0 직후: previous(=A)에서 출발해야 함
        let result = interp.interpolate()
        #expect(abs(result.coordinate.latitude - Self.A.latitude) < 0.0001)
        #expect(abs(result.coordinate.longitude - Self.A.longitude) < 0.0001)
    }

    @Test func interpolate_reachesTarget_after1Second() throws {
        let interp = LocationInterpolator()
        interp.resetTo(Self.A, 0)
        interp.setTarget(Self.B, heading: 45)

        Thread.sleep(forTimeInterval: 1.05)
        let result = interp.interpolate()

        #expect(abs(result.coordinate.latitude - Self.B.latitude) < 0.0001)
        #expect(abs(result.coordinate.longitude - Self.B.longitude) < 0.0001)
    }

    // MARK: - 핵심 버그 검증: setTarget 호출 시 점프 없음

    /// 수정 전 버그: animation 도중 setTarget을 호출하면 아이콘이 이전 목적지(B)로 순간이동한 뒤
    /// 새 목적지(C)로 이동했음. 수정 후에는 현재 시각적 위치에서 부드럽게 출발해야 함.
    @Test func setTarget_midAnimation_noJumpToPreviousTarget() throws {
        let interp = LocationInterpolator()
        interp.resetTo(Self.A, 0)
        interp.setTarget(Self.B, heading: 45)

        // 0.5초 대기 → animation 50% 진행 (아이콘은 A와 B 중간 어딘가)
        Thread.sleep(forTimeInterval: 0.5)
        let midResult = interp.interpolate()

        // 0.5초 시점 위치: A와 B 사이 (양쪽 끝이 아님)
        let midLat = midResult.coordinate.latitude
        #expect(midLat > Self.A.latitude + 0.0001)  // A보다 앞
        #expect(midLat < Self.B.latitude - 0.0001)  // B에 아직 못 미침

        // animation 도중 새 목적지(C)로 setTarget
        interp.setTarget(Self.C, heading: 90)

        // t=0 직후: 현재 시각적 위치(중간 지점) 근처에서 출발해야 함
        // 수정 전(버그): B로 점프 → latitude ≈ B.latitude = 37.501
        // 수정 후(정상): 중간 지점 근처 → latitude ≈ 37.5005
        let afterSetResult = interp.interpolate()
        let jumpedToB = abs(afterSetResult.coordinate.latitude - Self.B.latitude) < 0.0001

        #expect(!jumpedToB, "setTarget 후 이전 목적지(B)로 점프하면 안 됨")
        #expect(abs(afterSetResult.coordinate.latitude - midLat) < 0.0002,
                "setTarget 후 위치가 이전 시각적 위치(\(midLat)) 근처여야 함")
    }

    /// GPS가 matched(snapped) ↔ not-matched(rawGPS) 를 번갈아 반환하는 시나리오:
    /// 수정 전: snapped ↔ rawGPS 사이를 점프하며 깜빡임 발생
    /// 수정 후: 항상 현재 위치에서 부드럽게 전환
    @Test func alternatingGPS_noOscillation() throws {
        let interp = LocationInterpolator()
        let snapped = Self.B   // 경로 위 맵매칭 좌표
        let rawGPS  = Self.C   // 경로 밖 raw GPS 좌표

        interp.resetTo(snapped, 0)

        // tick 1: matched → snapped
        interp.setTarget(snapped, heading: 45)
        Thread.sleep(forTimeInterval: 1.0)

        // tick 2: not-matched → rawGPS
        interp.setTarget(rawGPS, heading: 90)
        let afterTick2Start = interp.interpolate()

        // 수정 후: snapped에서 시작 (t≈0, previous=snapped)
        // 수정 전(버그): rawGPS에서 역으로 점프 → snapped로 순간이동
        #expect(abs(afterTick2Start.coordinate.latitude - snapped.latitude) < 0.0002,
                "tick2 시작 시 snapped 근처여야 함, 실제: \(afterTick2Start.coordinate.latitude)")

        Thread.sleep(forTimeInterval: 1.0)

        // tick 3: matched → snapped (다시)
        interp.setTarget(snapped, heading: 45)
        let afterTick3Start = interp.interpolate()

        // 수정 후: rawGPS 근처에서 시작
        #expect(abs(afterTick3Start.coordinate.latitude - rawGPS.latitude) < 0.0002,
                "tick3 시작 시 rawGPS 근처여야 함, 실제: \(afterTick3Start.coordinate.latitude)")
    }

    // MARK: - heading 보간

    @Test func heading_interpolatesOnShortestArc() {
        let interp = LocationInterpolator()
        interp.resetTo(Self.A, 350)  // 350°
        interp.setTarget(Self.B, heading: 10)  // 10° (최단호: +20°)

        Thread.sleep(forTimeInterval: 0.5)
        let result = interp.interpolate()

        // 350 → 10: 최단호 경로로 가면 t=0.5에서 약 360° ≈ 0°
        let h = result.heading
        #expect(h > 355 || h < 5, "heading 최단호 보간 실패: \(h)")
    }
}
