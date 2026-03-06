import MapKit

// MARK: - Transport Mode

enum TransportMode: String, Sendable {
    case automobile
    case walking

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .automobile: return .automobile
        case .walking: return .walking
        }
    }

    var displayName: String {
        switch self {
        case .automobile: return "자동차"
        case .walking: return "도보"
        }
    }

    var iconName: String {
        switch self {
        case .automobile: return "car.fill"
        case .walking: return "figure.walk"
        }
    }
}
