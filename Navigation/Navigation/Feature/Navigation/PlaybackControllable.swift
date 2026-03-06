import Combine

protocol PlaybackControllable: AnyObject {
    var isPlayingPublisher: CurrentValueSubject<Bool, Never> { get }
    var progressPublisher: CurrentValueSubject<Double, Never> { get }
    var speedMultiplierPublisher: CurrentValueSubject<Double, Never> { get }

    func play()
    func pause()
    func stop()
    func cycleSpeed()
}
