import Foundation
import Network
import Combine

final class NetworkMonitor {

    static let shared = NetworkMonitor()

    // MARK: - Publishers

    let isConnectedPublisher = CurrentValueSubject<Bool, Never>(true)

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.navigation.networkMonitor")

    // MARK: - Init

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnectedPublisher.send(isConnected)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Public

    var isConnected: Bool {
        isConnectedPublisher.value
    }
}
