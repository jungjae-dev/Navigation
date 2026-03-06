import Combine
import MapKit
@testable import Navigation

final class MockSearchService: SearchProviding {

    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    var mockSearchResults: [Place] = []
    var shouldThrow: LBSError?

    var currentRegion: MKCoordinateRegion?

    func updateRegion(_ region: MKCoordinateRegion) { currentRegion = region }

    func updateQuery(_ fragment: String) {}

    func search(for completion: SearchCompletion) async throws -> [Place] {
        if let error = shouldThrow { throw error }
        return mockSearchResults
    }

    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] {
        if let error = shouldThrow { throw error }
        return mockSearchResults
    }

    func cancelCurrentSearch() {}
}
