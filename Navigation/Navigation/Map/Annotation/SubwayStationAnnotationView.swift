import MapKit
import UIKit

final class SubwayStationAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "SubwayStationAnnotationView"

    private let dotView = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        backgroundColor = .clear
        canShowCallout = false

        dotView.frame = CGRect(x: 1, y: 1, width: 20, height: 20)
        dotView.layer.cornerRadius = 10
        dotView.layer.borderWidth = 2.5
        dotView.layer.borderColor = UIColor.white.cgColor
        dotView.backgroundColor = UIColor(hex: "#888888") ?? .gray
        addSubview(dotView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        dotView.backgroundColor = UIColor(hex: "#888888") ?? .gray
    }

    func configure(with annotation: SubwayStationAnnotation) {
        dotView.backgroundColor = UIColor(hex: annotation.primaryColor) ?? .gray

        // 환승역: 테두리를 더 두껍게 표시
        if annotation.isTransfer {
            dotView.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
            dotView.layer.cornerRadius = 12
            frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        } else {
            dotView.frame = CGRect(x: 1, y: 1, width: 20, height: 20)
            dotView.layer.cornerRadius = 10
            frame = CGRect(x: 0, y: 0, width: 22, height: 22)
        }
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else { return nil }
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}
