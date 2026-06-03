import MapKit

final class SubwayStationAnnotation: NSObject, MKAnnotation {
    let station: SubwayStation
    let lines: SubwayLines

    var coordinate: CLLocationCoordinate2D { station.coordinate }
    var title: String? { station.name }

    init(station: SubwayStation, lines: SubwayLines) {
        self.station = station
        self.lines = lines
        super.init()
    }

    /// 첫 번째 호선 색상 (대표색)
    var primaryColor: String {
        for lineName in station.lines {
            if let info = lines[lineName] { return info.color }
        }
        return "#888888"
    }

    /// 환승역 여부
    var isTransfer: Bool { station.lines.count > 1 }
}
