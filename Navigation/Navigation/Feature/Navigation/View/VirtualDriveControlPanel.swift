import SwiftUI
import Combine

@MainActor
final class VirtualDriveControlViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var isPlaying: Bool = false
    @Published var speedMultiplier: Double = 1.0
    @Published var isDragging: Bool = false

    private weak var driver: VirtualDriveDriver?
    private var cancellables = Set<AnyCancellable>()

    init(driver: VirtualDriveDriver) {
        self.driver = driver

        driver.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in
                guard let self, !self.isDragging else { return }
                self.progress = p
            }
            .store(in: &cancellables)

        driver.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPlaying = $0 }
            .store(in: &cancellables)

        driver.speedMultiplierPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speedMultiplier = $0 }
            .store(in: &cancellables)
    }

    func cancel() {
        cancellables.removeAll()
    }

    func playPause() {
        guard let driver else { return }
        isPlaying ? driver.pause() : driver.play()
    }

    func prevStep() { driver?.seekToPreviousStep() }
    func nextStep() { driver?.seekToNextStep() }
    func cycleSpeed() { driver?.cycleSpeed() }

    func onSliderCommitted() {
        isDragging = false
        driver?.seek(to: progress)
    }
}

struct VirtualDriveControlPanel: View {
    @ObservedObject var viewModel: VirtualDriveControlViewModel

    var body: some View {
        HStack(spacing: 0) {
            // 이전 스텝
            controlButton(icon: "backward.end.fill") { viewModel.prevStep() }

            // 재생/일시정지
            controlButton(icon: viewModel.isPlaying ? "pause.fill" : "play.fill") { viewModel.playPause() }

            // 다음 스텝
            controlButton(icon: "forward.end.fill") { viewModel.nextStep() }

            // 진행 슬라이더
            Slider(
                value: $viewModel.progress,
                in: 0...1,
                onEditingChanged: { editing in
                    viewModel.isDragging = editing
                    if !editing { viewModel.onSliderCommitted() }
                }
            )
            .tint(.blue)
            .padding(.horizontal, 8)

            // 속도 배수
            Button(action: { viewModel.cycleSpeed() }) {
                Text(speedLabel)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.blue)
                    .frame(width: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var speedLabel: String {
        let v = viewModel.speedMultiplier
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(v))x"
            : String(format: "%.1gx", v)
    }

    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 36)
        }
    }
}
