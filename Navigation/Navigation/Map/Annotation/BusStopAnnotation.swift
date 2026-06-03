import MapKit

final class BusStopAnnotation: NSObject, MKAnnotation {
    let busStop: BusStop

    var coordinate: CLLocationCoordinate2D { busStop.coordinate }
    var title: String? { busStop.name }

    init(busStop: BusStop) {
        self.busStop = busStop
        super.init()
    }
}
