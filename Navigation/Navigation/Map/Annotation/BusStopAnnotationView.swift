import MapKit
import UIKit

/// 버스 정류소 마커 — 위치만 표시하는 작은 원형 점
/// 따릉이 마커는 잔여 수를 표시해 큰 마커가 필요하지만, 버스는 위치만 알면 되므로 작은 점으로 표시
/// 선택 시 점이 커지며 버스 아이콘이 나타나 강조됨
final class BusStopAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "BusStopAnnotationView"

    private static let dotSize: CGFloat = 16
    private static let selectedScale: CGFloat = 2.4
    private static let fillColor = UIColor(red: 0x33 / 255, green: 0x66 / 255, blue: 0xCC / 255, alpha: 1)

    private let glyphImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "bus.fill"))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        glyphImageView.alpha = 0
    }

    private func configure() {
        let size = Self.dotSize
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        backgroundColor = Self.fillColor
        layer.cornerRadius = size / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2

        addSubview(glyphImageView)
        NSLayoutConstraint.activate([
            glyphImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.6),
            glyphImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6)
        ])

        canShowCallout = false
        displayPriority = .required
        collisionMode = .circle
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        let changes = {
            self.transform = selected ? CGAffineTransform(scaleX: Self.selectedScale, y: Self.selectedScale) : .identity
            self.glyphImageView.alpha = selected ? 1 : 0
        }

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: changes)
        } else {
            changes()
        }
    }
}
