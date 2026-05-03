import Foundation
import UIKit
import MapKit
import CoreLocation
import Combine

/// MKMapView에 user 위치 마커를 부착하는 presenter.
///
/// **사용 예**:
/// ```
/// let mapView = TouchObservableMapView()
/// let presenter = UserLocationPresenter(mapView: mapView)
/// presenter.attach()
///
/// mapView.onUserTouch = { [weak presenter] in
///     presenter?.userDidInteractWithMap()
/// }
///
/// func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
///     if let v = presenter.makeAnnotationView(for: annotation) { return v }
///     // ...
/// }
/// ```
final class UserLocationPresenter {

    enum TrackingMode { case none, follow, followWithHeading }

    // MARK: - Public

    var onTrackingModeChanged: ((TrackingMode) -> Void)?

    private(set) var trackingMode: TrackingMode = .none {
        didSet {
            applyTrackingMode(animated: true)
            updateAnnotationView()
            onTrackingModeChanged?(trackingMode)
        }
    }

    // MARK: - Private

    private weak var mapView: MKMapView?
    private let locationService: LocationService
    private let annotation = UserLocationAnnotation()
    private let interpolator = LocationInterpolator()
    private var displayLink: CADisplayLink?
    private var cancellables = Set<AnyCancellable>()
    private var isAttached = false

    /// 첫 GPS 좌표 수신 여부 — interpolator 초기화/카메라 추적 가드
    private var hasReceivedFirstLocation = false

    /// 컴파스 heading — location.course가 invalid일 때 fallback
    private var lastCompassHeading: CLLocationDirection = 0

    // MARK: - Init

    init(mapView: MKMapView, locationService: LocationService = .shared) {
        self.mapView = mapView
        self.locationService = locationService
    }

    // MARK: - Lifecycle

    func attach() {
        guard let mapView, !isAttached else { return }
        isAttached = true

        mapView.showsUserLocation = false
        mapView.addAnnotation(annotation)

        // 캐시된 위치로 초기 시드 — (0,0) → 실제 위치 보간 회피
        if let cached = locationService.cachedLocation, cached.horizontalAccuracy >= 0 {
            annotation.coordinate = cached.coordinate
            interpolator.resetTo(cached.coordinate, 0)
            hasReceivedFirstLocation = true
        }

        bindLocationService()
        startDisplayLink()
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false

        stopDisplayLink()
        if let mapView {
            mapView.removeAnnotation(annotation)
        }
        cancellables.removeAll()
    }

    // MARK: - Tracking Mode

    func setTrackingMode(_ mode: TrackingMode) {
        trackingMode = mode
    }

    /// 순환: none → follow → followWithHeading → none
    @discardableResult
    func cycleTrackingMode() -> TrackingMode {
        let next: TrackingMode = switch trackingMode {
        case .none: .follow
        case .follow: .followWithHeading
        case .followWithHeading: .none
        }
        trackingMode = next
        return next
    }

    /// TouchObservableMapView.onUserTouch 콜백에서 호출 — 사용자 터치 시 tracking 해제
    func userDidInteractWithMap() {
        if trackingMode != .none {
            setTrackingMode(.none)
        }
    }

    // MARK: - Delegate Helper

    /// MapVC delegate.viewFor에서 호출
    func makeAnnotationView(for annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation === self.annotation else { return nil }
        let identifier = "UserLocationAnnotation"
        let view: UserLocationAnnotationView
        if let reused = mapView?.dequeueReusableAnnotationView(withIdentifier: identifier)
            as? UserLocationAnnotationView {
            reused.annotation = annotation
            view = reused
        } else {
            view = UserLocationAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        }
        configureAnnotationView(view)
        return view
    }

    // MARK: - Private: Bindings

    private func bindLocationService() {
        // 좌표 (1Hz) → interpolator target
        // location.course invalid 시 컴파스 heading fallback
        locationService.locationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self else { return }
                let heading = location.course >= 0 ? location.course : lastCompassHeading
                interpolator.setTarget(location.coordinate, heading: heading)
                hasReceivedFirstLocation = true
            }
            .store(in: &cancellables)

        // 컴파스 — 별도 저장만, interpolator는 건드리지 않음
        locationService.headingPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heading in
                guard let self else { return }
                lastCompassHeading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            }
            .store(in: &cancellables)
    }

    // MARK: - Private: Display Link (60fps)

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        let result = interpolator.interpolate()
        annotation.coordinate = result.coordinate
        annotation.heading = result.heading

        if trackingMode != .none {
            applyTrackingMode(animated: false)
        }
        updateAnnotationView()
    }

    // MARK: - Private: Camera Tracking

    private func applyTrackingMode(animated: Bool) {
        guard let mapView, hasReceivedFirstLocation else { return }
        let coord = annotation.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return }

        switch trackingMode {
        case .none:
            break
        case .follow:
            mapView.setCenter(coord, animated: animated)
        case .followWithHeading:
            let camera = mapView.camera.copy() as? MKMapCamera ?? MKMapCamera()
            camera.centerCoordinate = coord
            camera.heading = annotation.heading
            mapView.setCamera(camera, animated: animated)
        }
    }

    // MARK: - Private: Annotation View

    private func updateAnnotationView() {
        guard let mapView,
              let view = mapView.view(for: annotation) as? UserLocationAnnotationView else { return }
        configureAnnotationView(view)
    }

    /// MKAnnotationView는 지도 회전을 따라가지 않음 (screen 좌표 고정).
    /// 카메라 회전을 빼야 화살표가 월드 기준 진행 방향을 가리킴.
    private func configureAnnotationView(_ view: UserLocationAnnotationView) {
        view.setHeadingArrowVisible(trackingMode != .none)
        let mapHeading = mapView?.camera.heading ?? 0
        view.updateHeading(annotation.heading - mapHeading)
    }
}
