import UIKit
import MapKit
import CoreLocation

/// user 위치 표시 view (파란 점 + heading 화살표)
final class UserLocationAnnotationView: MKAnnotationView {

    // MARK: - Subviews

    private let dot: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBlue
        v.layer.cornerRadius = 9
        v.layer.borderWidth = 3
        v.layer.borderColor = UIColor.white.cgColor
        return v
    }()

    private let arrowLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.systemBlue.cgColor
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 14, y: 0))
        path.addLine(to: CGPoint(x: 7, y: 10))
        path.addLine(to: CGPoint(x: 21, y: 10))
        path.close()
        layer.path = path.cgPath
        layer.frame = CGRect(x: 0, y: -10, width: 28, height: 20)
        return layer
    }()

    private var hasArrow: Bool = false

    // MARK: - Init

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        canShowCallout = false
        isUserInteractionEnabled = false

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        dot.frame = CGRect(x: 5, y: 5, width: 18, height: 18)
        addSubview(dot)
    }

    // MARK: - Heading

    func setHeadingArrowVisible(_ visible: Bool) {
        if visible && !hasArrow {
            layer.addSublayer(arrowLayer)
            hasArrow = true
        } else if !visible && hasArrow {
            arrowLayer.removeFromSuperlayer()
            hasArrow = false
        }
    }

    /// 0° = 북쪽
    func updateHeading(_ heading: CLLocationDirection) {
        transform = CGAffineTransform(rotationAngle: heading * .pi / 180)
    }
}
