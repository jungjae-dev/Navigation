import MapKit
import UIKit

/// 따릉이 정류소 마커 — 시스템 MKMarkerAnnotationView + 잔여 자전거 수 라벨
final class BikeAnnotationView: MKMarkerAnnotationView {

    static let reuseIdentifier = "BikeStationAnnotation"

    private static let brandGreen = UIColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1)

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func configure() {
        markerTintColor = Self.brandGreen
        glyphTintColor = .yellow
        glyphImage = nil
        selectedGlyphImage = nil
        canShowCallout = false
        displayPriority = .required

        if let bike = (annotation as? BikeAnnotation)?.station {
            glyphText = "\(bike.availableBikes)"
        } else {
            glyphText = nil
        }
    }
}
