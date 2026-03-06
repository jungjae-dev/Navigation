import MapKit

extension Route {

    var mkPolyline: MKPolyline {
        MKPolyline(coordinates: polylineCoordinates, count: polylineCoordinates.count)
    }
}

extension Place {

    var mkMapItem: MKMapItem {
        AppleModelConverter.mapItem(from: self)
    }
}
