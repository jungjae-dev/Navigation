import Combine
import MapKit

protocol SearchProviding: AnyObject {

    var completionsPublisher: CurrentValueSubject<[SearchCompletion], Never> { get }
    var queryCompletionsPublisher: CurrentValueSubject<[SearchCompletion], Never> { get }
    var isSearchingPublisher: CurrentValueSubject<Bool, Never> { get }
    var errorPublisher: PassthroughSubject<Error, Never> { get }
    var currentRegion: MKCoordinateRegion? { get }

    func updateRegion(_ region: MKCoordinateRegion)
    func updateQuery(_ fragment: String)
    func search(for completion: SearchCompletion) async throws -> [Place]
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place]
    func cancelCurrentSearch()
}
