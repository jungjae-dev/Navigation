import MapKit

/// 실시간 혼잡 마커 (장소 좌표 + 표시 단계)
final class CongestionAnnotation: NSObject, MKAnnotation {
    let place: CongestionPlace
    /// 현재 표시 단계 (offset 0=실시간, 이후 슬라이더로 예측 단계 반영 — US2)
    var level: CongestionLevel

    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.areaName }
    var subtitle: String? { level.displayName }

    init(place: CongestionPlace, level: CongestionLevel) {
        self.place = place
        self.level = level
    }
}
