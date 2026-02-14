import MapKit
import UIKit

final class RouteOverlayRenderer: MKPolylineRenderer {

    init(polyline: MKPolyline, isPrimary: Bool) {
        super.init(polyline: polyline)
        strokeColor = isPrimary ? Theme.Colors.primary : Theme.Colors.secondaryLabel.withAlphaComponent(0.5)
        lineWidth = isPrimary ? 5.0 : 3.0
        lineCap = .round
        lineJoin = .round
    }
}
