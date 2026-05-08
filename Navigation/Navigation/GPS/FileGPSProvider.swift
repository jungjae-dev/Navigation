import CoreLocation
import Combine

/// GPX 파일 재생 GPS Provider
/// LocationSimulator를 사용하여 GPX 파일의 좌표를 타임스탬프 간격으로 재생
final class FileGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        simulator.simulatedLocationPublisher.eraseToAnyPublisher()
    }

    // MARK: - Public Publishers (LocationSimulator 위임)

    var isPlayingPublisher: CurrentValueSubject<Bool, Never> {
        simulator.isPlayingPublisher
    }
    var progressPublisher: CurrentValueSubject<Double, Never> {
        simulator.progressPublisher
    }
    var speedMultiplierPublisher: CurrentValueSubject<Double, Never> {
        simulator.speedMultiplierPublisher
    }
    /// 시뮬레이션 위치 발행 (LocationService.override 등에 연결 가능)
    var simulatedLocationPublisher: PassthroughSubject<CLLocation, Never> {
        simulator.simulatedLocationPublisher
    }

    // MARK: - Private

    private let simulator = LocationSimulator()
    private let fileURL: URL

    // MARK: - Init

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - GPSProviding

    func start() {
        guard simulator.load(fileURL: fileURL) else {
            print("[FileGPSProvider] 파일 로드 실패: \(fileURL.lastPathComponent)")
            return
        }
        simulator.play(loop: true)
    }

    func stop() {
        simulator.stop()
    }

    // MARK: - Playback Control (LocationSimulator 위임)

    func play() { simulator.play() }
    func pause() { simulator.pause() }
    func cycleSpeed() { simulator.cycleSpeed() }
}
