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

    /// CLLocation 발행 (GPXRecorder, MapView 등 위치 표시 용도)
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        simulator.simulatedLocationPublisher.eraseToAnyPublisher()
    }

    /// engine 입력 — 폴리라인 위 좌표를 GPSData로 변환 (isValid: true)
    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsSubject.eraseToAnyPublisher()
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
    private let gpsSubject = PassthroughSubject<GPSData, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // simulator의 CLLocation → GPSData 변환
        simulator.simulatedLocationPublisher
            .sink { [weak self] location in
                self?.handleLocation(location)
            }
            .store(in: &cancellables)
    }

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

    // MARK: - Private

    private func handleLocation(_ location: CLLocation) {
        let gpsData = GPSData(
            coordinate: location.coordinate,
            heading: location.course >= 0 ? location.course : 0,
            speed: max(0, location.speed),
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            isValid: true
        )
        gpsSubject.send(gpsData)
    }
}
