import Foundation
import MapKit

/// 번들 핫스팟(장소명→좌표) 1개. citydata 응답엔 좌표가 없어 번들 매핑이 필수(research R2).
struct Hotspot: Decodable, Sendable {
    let areaName: String
    let areaCode: String
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// 번들 `hotspots.json` 로드 + 가시 영역 필터.
/// (시드: 주요 9곳. 전체 ~120곳 목록으로 확장 예정)
final class HotspotCatalog {

    let hotspots: [Hotspot]
    private let byName: [String: Hotspot]

    init(hotspots: [Hotspot]) {
        self.hotspots = hotspots
        self.byName = Dictionary(hotspots.map { ($0.areaName, $0) }, uniquingKeysWith: { a, _ in a })
    }

    convenience init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "hotspots", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Hotspot].self, from: data) else {
            return nil
        }
        self.init(hotspots: list)
    }

    func hotspot(named name: String) -> Hotspot? { byName[name] }

    /// 보이는 지도 영역 안의 장소명 (뷰포트 우선 로딩, FR-007a)
    func visibleAreaNames(in rect: MKMapRect) -> [String] {
        hotspots
            .filter { rect.contains(MKMapPoint($0.coordinate)) }
            .map(\.areaName)
    }
}
