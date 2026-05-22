import Foundation
import CoreLocation
import Combine

/// 가상 주행 전용 GPS 소스
///
/// **Real/File과의 차이**:
/// - Real/File은 외부 이벤트(CLLocationManager / GPX 파일)가 트리거
/// - VirtualDriveDriver는 내부 timer + 폴리라인 알고리즘이 트리거
/// - 데이터가 이미 폴리라인 위에 있는 pre-matched 좌표 (이탈 불가능)
///
/// **Lifecycle**:
/// - 가상주행 버튼 탭 → start(polyline:) — 새 인스턴스 생성
/// - 안내 종료 → stop() + 인스턴스 폐기
/// - 일회성. 다음 가상주행 시 새 인스턴스.
///
/// **GPSProviding을 따르지 않음**:
/// - LocationService.activeProvider는 Real/File 전용 (raw GPS)
/// - 가상주행은 LocationService를 우회하고 NavigationSessionManager에 직접 연결
final class VirtualDriveDriver {

    // MARK: - Output Publishers

    /// 위치 스트림 — 표시·엔진 통합 (GPSProviding.locationPublisher 와 동일 컨벤션)
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        simulator.simulatedLocationPublisher.eraseToAnyPublisher()
    }

    // MARK: - Playback State (UI 표시용)

    var isPlayingPublisher: CurrentValueSubject<Bool, Never> {
        simulator.isPlayingPublisher
    }
    var progressPublisher: CurrentValueSubject<Double, Never> {
        simulator.progressPublisher
    }
    var speedMultiplierPublisher: CurrentValueSubject<Double, Never> {
        simulator.speedMultiplierPublisher
    }

    // MARK: - Configuration

    private static let defaultSpeedMPS: Double = 13.9   // ~50 km/h
    private static let walkingSpeedMPS: Double = 1.4    // ~5 km/h

    // MARK: - Private

    private let simulator = LocationSimulator()

    // MARK: - Lifecycle

    /// 가상 주행 시작 — 폴리라인 + 교통 모드로 시뮬레이션 시작
    func start(polyline: [CLLocationCoordinate2D], transportMode: TransportMode = .automobile) {
        let speed = transportMode == .walking ? Self.walkingSpeedMPS : Self.defaultSpeedMPS
        simulator.load(polyline: polyline, speedMPS: speed)
        simulator.play(loop: true)  // 끝까지 재생 후 처음부터 반복
    }

    /// 가상 주행 정지 (lifecycle 종료 — 다시 start 호출 시 처음부터)
    func stop() {
        simulator.stop()
    }

    // MARK: - Playback Control (속도/일시정지)

    func play() {
        simulator.play(loop: true)
    }

    func pause() {
        simulator.pause()
    }

    /// 0.5x → 1x → 2x → 4x → 0.5x 순환
    func cycleSpeed() {
        simulator.cycleSpeed()
    }

    /// 직접 속도 배수 지정
    func setSpeedMultiplier(_ multiplier: Double) {
        simulator.speedMultiplier = max(0.1, min(10.0, multiplier))
    }

    // MARK: - Seek

    func seek(to progress: Double) {
        simulator.seek(to: progress)
    }

    func seekToNextStep() {
        simulator.seekToNextBreakpoint()
    }

    func seekToPreviousStep() {
        simulator.seekToPreviousBreakpoint()
    }

    /// Route steps 기반으로 스텝 브레이크포인트 계산 후 로드
    func loadSteps(_ steps: [RouteStep]) {
        guard !steps.isEmpty else { return }
        let totalDistance = steps.reduce(0) { $0 + $1.distance }
        guard totalDistance > 0 else { return }

        var accumulated: CLLocationDistance = 0
        var breakpoints: [Double] = []
        for step in steps {
            breakpoints.append(accumulated / totalDistance)
            accumulated += step.distance
        }
        simulator.loadBreakpoints(breakpoints)
    }
}
