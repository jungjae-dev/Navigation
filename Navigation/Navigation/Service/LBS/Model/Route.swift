import CoreLocation

struct Route: Sendable {
    let id: String
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    var name: String
    let steps: [RouteStep]
    let polylineCoordinates: [CLLocationCoordinate2D]
    let transportMode: TransportMode
}

// MARK: - Formatting

extension Route {

    var formattedDistance: String {
        let km = distance / 1000.0
        if km < 1 {
            return String(format: "%dm", Int(distance))
        } else {
            return String(format: "%.1fkm", km)
        }
    }

    var formattedTravelTime: String {
        let totalMinutes = Int(expectedTravelTime / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)분"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours)시간"
            }
            return "\(hours)시간 \(minutes)분"
        }
    }

    var estimatedArrivalTime: Date {
        Date().addingTimeInterval(expectedTravelTime)
    }

    var formattedArrivalTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: estimatedArrivalTime) + " 도착"
    }
}
