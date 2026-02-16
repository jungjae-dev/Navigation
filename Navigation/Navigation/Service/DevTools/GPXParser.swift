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
        return locations
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
