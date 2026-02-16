import MapKit
import UIKit

final class RouteOverlayRenderer: MKPolylineRenderer {

    private let isPrimary: Bool

    nonisolated init(polyline: MKPolyline, isPrimary: Bool) {
        self.isPrimary = isPrimary
        super.init(polyline: polyline)
        MainActor.assumeIsolated {
            strokeColor = isPrimary ? Theme.Colors.primary : Theme.Colors.secondaryLabel.withAlphaComponent(0.5)
            lineWidth = isPrimary ? 5.0 : 3.0
            lineCap = .round
            lineJoin = .round
        }
    }

    nonisolated override init(overlay: any MKOverlay) {
        self.isPrimary = false
        super.init(overlay: overlay)
    }
}
