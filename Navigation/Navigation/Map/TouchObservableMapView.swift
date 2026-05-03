import MapKit

/// hitTest로 사용자 터치를 감지하는 MKMapView (MapKit 동작 그대로 유지)
final class TouchObservableMapView: MKMapView {

    /// 사용자 터치 시 호출 — auto-tracking 자동 해제 등에 사용
    var onUserTouch: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let event, event.type == .touches, bounds.contains(point) {
            onUserTouch?()
        }
        return super.hitTest(point, with: event)
    }
}
