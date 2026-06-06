import MapKit
import UIKit

/// 버스 정류소 마커 — 시스템 MKMarkerAnnotationView + 버스 SF Symbol
/// 선택 시 시스템이 자동으로 확대/강조 (따릉이 마커와 동일 방식)
final class BusStopAnnotationView: MKMarkerAnnotationView {

    static let reuseIdentifier = "BusStopAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure()
    }

    private func configure() {
        markerTintColor = UIColor(red: 0x33 / 255, green: 0x66 / 255, blue: 0xCC / 255, alpha: 1)
        glyphImage = UIImage(systemName: "bus")
        glyphTintColor = .white
        canShowCallout = false
        displayPriority = .required
    }
}
