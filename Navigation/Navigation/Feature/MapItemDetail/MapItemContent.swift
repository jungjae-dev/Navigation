import UIKit
import CoreLocation

/// 지도 위 항목(POI, 따릉이, 향후 버스/지하철 등) 상세 시트의 컨텐츠 추상화
/// MapItemDetailViewController 가 scaffold (헤더 + 컨텐츠 호스트 + 푸터) 만 담당하고,
/// 각 타입은 이 프로토콜을 구현해 자기 컨텐츠를 제공
protocol MapItemContent: AnyObject {
    /// 헤더 좌측 아이콘
    var iconImage: UIImage? { get }
    /// 헤더 제목
    var title: String { get }
    /// 같은 항목인지 비교용 식별자
    var identifier: String { get }
    /// 컨텐츠 영역에 표시할 UIView (자신이 소유 + 관리)
    var contentView: UIView { get }
    /// 하단 footer 액션 버튼들
    var footerActions: [MapItemAction] { get }
    /// 현재 위치 기반 거리 갱신 — 필요 없는 타입은 기본 구현 (no-op) 사용
    func updateDistance(from coordinate: CLLocationCoordinate2D?)
}

extension MapItemContent {
    func updateDistance(from coordinate: CLLocationCoordinate2D?) {}
}

/// MapItemContent 가 반환하는 하단 액션 버튼 디스크립터
struct MapItemAction {
    let title: String
    let iconName: String?
    let style: DrawerActionButton.Style
    let handler: () -> Void
}
