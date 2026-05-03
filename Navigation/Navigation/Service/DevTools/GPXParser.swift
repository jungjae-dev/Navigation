import Foundation
import CoreLocation

final class GPXParser: NSObject {

    // MARK: - Properties

    private var locations: [CLLocation] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    private var currentElement: String = ""
    private var currentText: String = ""

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Public

    func parse(data: Data) -> [CLLocation] {
        locations = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return Self.fillCourses(locations)
    }

    /// GPX 표준에 course가 없으므로 인접 좌표 bearing으로 채움 (마지막 점은 직전 bearing 유지)
    private static func fillCourses(_ locations: [CLLocation]) -> [CLLocation] {
        guard locations.count >= 2 else { return locations }
        var result: [CLLocation] = []
        result.reserveCapacity(locations.count)

        for i in 0..<locations.count {
            let course: CLLocationDirection
            if i + 1 < locations.count {
                course = bearing(from: locations[i].coordinate, to: locations[i + 1].coordinate)
            } else {
                course = result.last?.course ?? 0
            }

            let original = locations[i]
            // courseAccuracy 명시 — 생략 시 .course가 -1로 invalidate됨
            let withCourse = CLLocation(
                coordinate: original.coordinate,
                altitude: original.altitude,
                horizontalAccuracy: original.horizontalAccuracy,
                verticalAccuracy: original.verticalAccuracy,
                course: course,
                courseAccuracy: 0,
                speed: original.speed,
                speedAccuracy: 0,
                timestamp: original.timestamp
            )
            result.append(withCourse)
        }
        return result
    }

    private static func bearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    func parse(fileURL: URL) -> [CLLocation] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return parse(data: data)
    }
}

// MARK: - XMLParserDelegate

extension GPXParser: XMLParserDelegate {

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        MainActor.assumeIsolated {
            currentElement = elementName
            currentText = ""

            if elementName == "trkpt" || elementName == "wpt" || elementName == "rtept" {
                if let latStr = attributeDict["lat"], let lat = Double(latStr),
                   let lonStr = attributeDict["lon"], let lon = Double(lonStr) {
                    currentLat = lat
                    currentLon = lon
                }
                currentEle = nil
                currentTime = nil
            }
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        MainActor.assumeIsolated {
            currentText += string
        }
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        MainActor.assumeIsolated {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch elementName {
            case "ele":
                currentEle = Double(trimmed)

            case "time":
                currentTime = GPXParser.dateFormatter.date(from: trimmed)
                    ?? GPXParser.fallbackDateFormatter.date(from: trimmed)

            case "trkpt", "wpt", "rtept":
                if let lat = currentLat, let lon = currentLon {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let altitude = currentEle ?? 0
                    let timestamp = currentTime ?? Date()

                    let location = CLLocation(
                        coordinate: coordinate,
                        altitude: altitude,
                        horizontalAccuracy: 5.0,
                        verticalAccuracy: 5.0,
                        timestamp: timestamp
                    )
                    locations.append(location)
                }
                currentLat = nil
                currentLon = nil
                currentEle = nil
                currentTime = nil

            default:
                break
            }
        }
    }
}
