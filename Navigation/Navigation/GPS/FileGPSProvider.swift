import CoreLocation
import Combine

/// GPX 파일 재생 GPS Provider
/// LocationSimulator를 사용하여 GPX 파일의 좌표를 타임스탬프 간격으로 재생
final class FileGPSProvider: GPSProviding {

    // MARK: - GPSProviding

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        simulator.simulatedLocationPublisher.eraseToAnyPublisher()
    }

    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsSubject.eraseToAnyPublisher()
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

    private let gpsSubject = PassthroughSubject<GPSData, Never>()
    private let simulator = LocationSimulator()
    private var cancellables = Set<AnyCancellable>()
    private let gpxFileURL: URL

    // MARK: - Init

    /// GPX 파일 URL로 초기화
    init(gpxFileURL: URL) {
        self.gpxFileURL = gpxFileURL

        // LocationSimulator의 CLLocation → GPSData 변환
        simulator.simulatedLocationPublisher
            .sink { [weak self] location in
                self?.handleLocation(location)
            }
            .store(in: &cancellables)
    }

    // MARK: - GPSProviding

    func start() {
        // GPX 파일 로드 후 재생
        guard simulator.load(gpxFileURL: gpxFileURL) else {
            print("[FileGPSProvider] GPX 파일 로드 실패: \(gpxFileURL.lastPathComponent)")
            return
        }
        simulator.play()
    }

    func stop() {
        simulator.stop()
    }

    // MARK: - Playback Control (LocationSimulator 위임)

    func play() { simulator.play() }
    func pause() { simulator.pause() }
    func cycleSpeed() { simulator.cycleSpeed() }

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
