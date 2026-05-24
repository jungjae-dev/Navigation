import MapKit
import UIKit

/// 따릉이 정류소 마커 — MKMarkerAnnotationView 와 유사한 풍선 모양
/// - 잔여 자전거 수에 따라 색상 변경
/// - 흰 테두리 없음, 어두운 글자
final class BikeAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "BikeStationAnnotation"

    // 마커 크기
    private static let markerWidth: CGFloat = 32
    private static let markerHeight: CGFloat = 38   // 꼬리 짧게 (38 - 32 = 6pt 꼬리)
    private static let tipHeight: CGFloat = 6
    private static var circleDiameter: CGFloat { markerWidth }
    private static var totalSize: CGSize { CGSize(width: markerWidth, height: markerHeight) }

    private let pinLayer = CAShapeLayer()
    private let countLabel = UILabel()

    override var annotation: MKAnnotation? {
        didSet { update() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
        update()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupView() {
        let bounds = CGRect(origin: .zero, size: Self.totalSize)
        frame = bounds
        backgroundColor = .clear
        canShowCallout = false
        displayPriority = .required

        // annotation 좌표 = 핀 끝(tip)
        centerOffset = CGPoint(x: 0, y: -Self.markerHeight / 2 + Self.tipHeight / 2)

        // 핀 path (시스템 마커와 유사한 풍선 모양)
        pinLayer.path = Self.makePinPath().cgPath
        pinLayer.strokeColor = Self.glyphColor.cgColor
        pinLayer.lineWidth = 1.5
        pinLayer.shadowColor = UIColor.black.cgColor
        pinLayer.shadowOpacity = 0.25
        pinLayer.shadowOffset = CGSize(width: 0, height: 2)
        pinLayer.shadowRadius = 2
        pinLayer.shadowPath = pinLayer.path
        layer.addSublayer(pinLayer)

        // 잔여 자전거 수 라벨 (원형 영역 중앙)
        countLabel.frame = CGRect(x: 0, y: 0, width: Self.markerWidth, height: Self.circleDiameter)
        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        countLabel.textColor = Self.glyphColor
        countLabel.textAlignment = .center
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.6
        addSubview(countLabel)
    }

    private func update() {
        guard let bike = (annotation as? BikeAnnotation)?.station else { return }
        pinLayer.fillColor = Self.color(for: bike.availableBikes).cgColor
        countLabel.text = "\(bike.availableBikes)"
    }

    // MARK: - Path

    /// 완전한 원 + 아래쪽에 작은 꼬리 — 단일 연속 path
    /// 원과 꼬리 outline 을 하나의 path 로 연결해서 fill rule 이슈 방지
    private static func makePinPath() -> UIBezierPath {
        let d = circleDiameter      // 원 지름
        let h = markerHeight        // 전체 높이
        let r = d / 2

        // 꼬리가 원에 부착되는 지점 (원 둘레 위)
        let tailHalfWidth: CGFloat = 5
        // 원 둘레에서 x = r ± tailHalfWidth 일 때의 y (하단부)
        let attachY = r + sqrt(r * r - tailHalfWidth * tailHalfWidth)
        // 원 중심 기준 angle
        let leftAttachAngle = atan2(attachY - r, -tailHalfWidth)   // 좌측 부착점 각도
        let rightAttachAngle = atan2(attachY - r, tailHalfWidth)   // 우측 부착점 각도
        let tipY = h

        let path = UIBezierPath()

        // 시작: 좌측 부착점
        path.move(to: CGPoint(x: r - tailHalfWidth, y: attachY))

        // 좌측 부착점 → 원의 위쪽을 돌아서 → 우측 부착점 (긴 호)
        path.addArc(
            withCenter: CGPoint(x: r, y: r),
            radius: r,
            startAngle: leftAttachAngle,
            endAngle: rightAttachAngle,
            clockwise: true   // 시각적 clockwise (SW → W → N → E → SE, 위쪽 통과)
        )

        // 우측 부착점 → 끝점 (살짝 오목하게)
        path.addQuadCurve(
            to: CGPoint(x: r, y: tipY),
            controlPoint: CGPoint(x: r + 1, y: tipY - 2)
        )

        // 끝점 → 좌측 부착점 (대칭)
        path.addQuadCurve(
            to: CGPoint(x: r - tailHalfWidth, y: attachY),
            controlPoint: CGPoint(x: r - 1, y: tipY - 2)
        )

        path.close()
        return path
    }

    // MARK: - Colors

    /// 마커 배경 색상 (따릉이 브랜드 녹색 통일)
    static func color(for availableBikes: Int) -> UIColor {
        UIColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1)  // #2EB86B 따릉이 녹색
    }

    /// 글자 색 (어두운 녹·회색 계열)
    static let glyphColor = UIColor(red: 0.07, green: 0.20, blue: 0.10, alpha: 1)
}
