import Foundation
import CoreLocation

// MARK: - Static Data Models (Gist JSON)

struct TransitDataVersion: Codable {
    let busStops: String
}

struct BusStop: Codable, Identifiable {
    let stId: String
    let arsId: String
    let name: String
    let lat: Double
    let lng: Double

    var id: String { stId }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

// MARK: - Gist Envelope (version + data)

struct BusStopsEnvelope: Codable {
    let version: String
    let data: [BusStop]
}

// MARK: - Service State

enum TransitDataState: Equatable {
    case loading
    case loaded(busStops: [BusStop])
    case failed(String)

    static func == (lhs: TransitDataState, rhs: TransitDataState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.failed(let a), .failed(let b)): return a == b
        case (.loaded, .loaded): return true
        default: return false
        }
    }
}

// MARK: - POI Layer State

struct POILayerState {
    var bikeEnabled: Bool = false
    var busEnabled: Bool = false
}

// MARK: - Realtime Models (API)

struct BusArrival: Identifiable {
    let id = UUID()
    let routeId: String
    let routeName: String
    let direction: String
    let firstArrivalMessage: String
    let secondArrivalMessage: String
    let routeType: BusRouteType
    let isLastBus: Bool
    var firstTime: String = ""   // 첫차 (HHmm)
    var lastTime: String = ""    // 막차 (HHmm)
    var term: String = ""        // 배차간격(분)
}

enum BusRouteType: Int, Codable {
    case trunk = 1         // 간선
    case branch = 2        // 지선
    case circular = 3      // 순환
    case express = 4       // 광역
    case incheon = 5       // 인천
    case airport = 6       // 공항
    case town = 11         // 마을
    case unknown = 0

    var color: String {
        switch self {
        case .trunk: return "#3366CC"
        case .branch: return "#66CC33"
        case .circular: return "#FFCC00"
        case .express, .airport: return "#FF6600"
        case .town: return "#00AA88"
        default: return "#888888"
        }
    }
}
