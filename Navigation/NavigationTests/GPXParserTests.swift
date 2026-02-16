import Testing
import CoreLocation
@testable import Navigation

struct GPXParserTests {

    private func gpxData(_ xml: String) -> Data {
        xml.data(using: .utf8)!
    }

    // MARK: - Parsing

    @Test func parseTrackPoints() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="37.5665" lon="126.9780">
                <ele>30</ele>
                <time>2025-01-01T09:00:00Z</time>
              </trkpt>
              <trkpt lat="37.4979" lon="127.0276">
                <ele>28</ele>
                <time>2025-01-01T09:05:00Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let parser = GPXParser()
        let locations = parser.parse(data: gpxData(xml))

        #expect(locations.count == 2)
        #expect(abs(locations[0].coordinate.latitude - 37.5665) < 0.001)
        #expect(abs(locations[0].coordinate.longitude - 126.9780) < 0.001)
        #expect(abs(locations[0].altitude - 30.0) < 0.1)
        #expect(abs(locations[1].coordinate.latitude - 37.4979) < 0.001)
    }

    @Test func parseWaypoints() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <wpt lat="37.5665" lon="126.9780">
            <ele>30</ele>
            <time>2025-01-01T09:00:00Z</time>
          </wpt>
        </gpx>
        """

        let parser = GPXParser()
        let locations = parser.parse(data: gpxData(xml))

        #expect(locations.count == 1)
        #expect(abs(locations[0].coordinate.latitude - 37.5665) < 0.001)
    }

    @Test func parseWithoutTimestamp() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="37.5665" lon="126.9780">
                <ele>30</ele>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let parser = GPXParser()
        let locations = parser.parse(data: gpxData(xml))

        #expect(locations.count == 1)
        #expect(locations[0].timestamp != .distantPast)
    }

    @Test func parseWithoutElevation() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="37.5665" lon="126.9780">
                <time>2025-01-01T09:00:00Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let parser = GPXParser()
        let locations = parser.parse(data: gpxData(xml))

        #expect(locations.count == 1)
        #expect(locations[0].altitude == 0.0)
    }

    @Test func emptyGPX() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"></gpx>
        """

        let parser = GPXParser()
        let locations = parser.parse(data: gpxData(xml))
        #expect(locations.isEmpty)
    }

    @Test func invalidData() {
        let parser = GPXParser()
        let locations = parser.parse(data: Data([0xFF, 0xFE]))
        #expect(locations.isEmpty)
    }

    @Test func multipleSegments() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="37.56" lon="126.97">
                <time>2025-01-01T09:00:00Z</time>
              </trkpt>
            </trkseg>
            <trkseg>
              <trkpt lat="37.50" lon="127.02">
                <time>2025-01-01T09:05:00Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """

        let parser = GPXParser()
        let locations = parser.parse(data: gpxData(xml))
        #expect(locations.count == 2)
    }
}
