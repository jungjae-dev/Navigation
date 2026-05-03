import MapKit

/// 맵매칭 디버그 트레일 — 매 tick 의 (GPS, matched) 쌍을 누적
/// 단일 MKOverlay 로 표현되어, 점이 수천 개여도 UIView 는 1개만 생성됨.
final class MapMatchTrailOverlay: NSObject, MKOverlay {

    struct Entry {
        let gpsCoord: CLLocationCoordinate2D
        let gpsHeading: CLLocationDirection      // NaN/음수면 화살표 미표시
        let matchedCoord: CLLocationCoordinate2D?
        let matchedHeading: CLLocationDirection?
    }

    // MARK: - MKOverlay

    /// MapKit 정렬용 — 첫 entry 기준. 비어 있으면 (0,0).
    var coordinate: CLLocationCoordinate2D {
        lock.withLock { _entries.first?.gpsCoord } ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    /// `.world` 사용 — 점이 추가될 때마다 boundingMapRect 갱신은 비용이 크고,
    /// MKMapView 는 어차피 visible rect 만 renderer 에 redraw 요청하므로 안전함.
    let boundingMapRect: MKMapRect = .world

    // MARK: - Data

    private var _entries: [Entry] = []
    private let lock = NSLock()
    private let maxEntries: Int

    init(maxEntries: Int = 5000) {
        self.maxEntries = maxEntries
        super.init()
    }

    // MARK: - Mutation (Main thread)

    func append(_ entry: Entry) {
        lock.withLock {
            _entries.append(entry)
            if _entries.count > maxEntries {
                _entries.removeFirst(_entries.count - maxEntries)
            }
        }
    }

    func clear() {
        lock.withLock { _entries.removeAll(keepingCapacity: true) }
    }

    /// 렌더 스레드(MapKit)에서 안전하게 스냅샷 읽기
    func snapshotEntries() -> [Entry] {
        lock.withLock { _entries }
    }
}
