import MapKit

/// 따릉이 정류소 annotation
final class BikeAnnotation: NSObject, MKAnnotation {
    let station: BikeStation

    var coordinate: CLLocationCoordinate2D { station.coordinate }
    var title: String? { station.stationName }
    // subtitle 은 사용 안 함 — 우리는 custom callout

    init(station: BikeStation) {
        self.station = station
        super.init()
    }
}
