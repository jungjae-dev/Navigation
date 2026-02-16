import Testing
import Combine
import CoreLocation
@testable import Navigation

struct GPXSimulatorTests {

    // MARK: - Helpers

    private func makeLocations() -> [CLLocation] {
        (0..<5).map { i in
            CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 37.56 - Double(i) * 0.01,
                    longitude: 126.97 + Double(i) * 0.01
                ),
                altitude: 30,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: Date().addingTimeInterval(Double(i) * 1.0)
            )
        }
    }

    // MARK: - Tests

    @Test func loadLocations() {
        let simulator = GPXSimulator()
        let locations = makeLocations()
        simulator.load(locations: locations)

        #expect(!simulator.isPlayingPublisher.value)
        #expect(simulator.progressPublisher.value == 0.0)
    }

    @Test func playEmitsLocations() async {
        let simulator = GPXSimulator()
        simulator.speedMultiplier = 100.0 // Fast playback
        simulator.load(locations: makeLocations())

        var received: [CLLocation] = []
        var cancellables = Set<AnyCancellable>()

        let expectation = expectation(description: "Locations emitted")

        simulator.simulatedLocationPublisher
            .sink { location in
                received.append(location)
                if received.count >= 5 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        simulator.play()

        await fulfillment(of: [expectation], timeout: 5.0)

        #expect(received.count == 5)
        cancellables.removeAll()
    }

    @Test func stopResetsProgress() {
        let simulator = GPXSimulator()
        simulator.load(locations: makeLocations())

        simulator.stop()

        #expect(!simulator.isPlayingPublisher.value)
        #expect(simulator.progressPublisher.value == 0.0)
    }

    @Test func resetClearsLocations() {
        let simulator = GPXSimulator()
        simulator.load(locations: makeLocations())

        simulator.reset()

        #expect(!simulator.isPlayingPublisher.value)
    }

    @Test func playWithNoLocationsDoesNothing() {
        let simulator = GPXSimulator()
        simulator.play()
        #expect(!simulator.isPlayingPublisher.value)
    }

    @Test func doublePlayIsNoOp() {
        let simulator = GPXSimulator()
        simulator.load(locations: makeLocations())
        simulator.play()

        #expect(simulator.isPlayingPublisher.value)

        // Second play should not restart
        simulator.play()
        #expect(simulator.isPlayingPublisher.value)

        simulator.stop()
    }

    // MARK: - XCTest Compatibility

    private func expectation(description: String) -> XCTestExpectation {
        XCTestExpectation(description: description)
    }

    private func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {
        // Simple polling-based wait for Swift Testing
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let allFulfilled = expectations.allSatisfy { $0.isFulfilled }
            if allFulfilled { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

// Minimal XCTestExpectation for Swift Testing
private final class XCTestExpectation: @unchecked Sendable {
    let description: String
    private(set) var isFulfilled = false

    init(description: String) {
        self.description = description
    }

    func fulfill() {
        isFulfilled = true
    }
}
