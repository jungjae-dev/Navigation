import MapKit
import UIKit

/// 운행 버스 마커 — 정류소 마커(파랑)와 구분되도록 초록 + 채워진 버스 아이콘
final class BusVehicleAnnotationView: MKMarkerAnnotationView {

    static let reuseIdentifier = "BusVehicleAnnotationView"

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
        markerTintColor = UIColor(red: 0x00 / 255, green: 0xA8 / 255, blue: 0x4D / 255, alpha: 1) // 초록
        glyphImage = UIImage(systemName: "bus.fill")
        glyphTintColor = .white
        canShowCallout = false
        displayPriority = .required
        zPriority = .max   // 정류소 마커/노선 라인 위에 표시
    }
}
