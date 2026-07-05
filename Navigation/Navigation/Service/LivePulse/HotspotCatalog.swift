import Foundation
import MapKit

/// 번들 핫스팟 1개 — 서울시 공식 121장소 영역(이름·코드·카테고리·중심·폴리곤).
struct Hotspot: Decodable, Sendable {
    let areaName: String
    let areaCode: String
    let category: String
    let center: [Double]      // [lat, lon]
    let rings: [[[Double]]]   // rings -> points -> [lat, lon]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: center.first ?? 0, longitude: center.count > 1 ? center[1] : 0)
    }

    /// 폴리곤 링 좌표 (면 색칠용)
    var polygonRings: [[CLLocationCoordinate2D]] {
        rings.map { ring in
            ring.compactMap { p in
                p.count >= 2 ? CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) : nil
            }
        }
    }
}

/// 번들 `hotspot_areas.json`(공식 121장소 영역) 로드 + 가시 영역 필터.
final class HotspotCatalog {

    let hotspots: [Hotspot]
    private let byName: [String: Hotspot]

    init(hotspots: [Hotspot]) {
        self.hotspots = hotspots
        self.byName = Dictionary(hotspots.map { ($0.areaName, $0) }, uniquingKeysWith: { a, _ in a })
    }

    convenience init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "hotspot_areas", withExtension: "json") else {
            print("[LivePulse] ✗ hotspot_areas.json 번들에서 못 찾음 (Copy Bundle Resources 누락)")
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Hotspot].self, from: data) else {
            print("[LivePulse] ✗ hotspot_areas.json 디코딩 실패")
            return nil
        }
        print("[LivePulse] hotspot_areas.json 로드 \(list.count)곳")
        self.init(hotspots: list)
    }

    func hotspot(named name: String) -> Hotspot? { byName[name] }

    /// 보이는 지도 영역 안의 장소명 (중심 기준, FR-007a)
    func visibleAreaNames(in rect: MKMapRect) -> [String] {
        hotspots
            .filter { rect.contains(MKMapPoint($0.coordinate)) }
            .map(\.areaName)
    }
}
