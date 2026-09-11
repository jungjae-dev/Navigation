import UIKit

/// DR-002 상태 스트립 + 실시간 인식 박스 오버레이.
/// 프로덕션 UI를 가리지 않는 투명 레이어 — 토글 off면 생성되지 않음 (DR-005).
final class ParkingDebugOverlayView: UIView {

    /// 스트립 롱프레스 → ARKit 내장 debugOptions 토글 (DR-001)
    var onToggleARDebugOptions: (() -> Void)?

    private let stripLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .systemGreen
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.text = " debug on — 관측 대기 "
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(stripLabel)
        NSLayoutConstraint.activate([
            stripLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 56),
            stripLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stripLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stripLabel.heightAnchor.constraint(equalToConstant: 18),
        ])

        // 스트립만 터치 허용 (롱프레스)
        stripLabel.isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(stripLongPressed))
        stripLabel.addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 스트립 외 영역은 터치 통과
        let view = super.hitTest(point, with: event)
        return view === stripLabel ? view : nil
    }

    func updateStrip(_ text: String?) {
        stripLabel.text = text.map { " \($0) " } ?? " debug on "
    }

    /// 인식 박스 — 채택 초록 / 기각 빨강+사유, 0.6초 후 소멸
    func flashBox(_ rect: CGRect, accepted: Bool, reason: String?) {
        let box = UIView(frame: rect)
        box.layer.borderColor = accepted ? UIColor.systemGreen.cgColor : UIColor.systemRed.cgColor
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 4
        box.isUserInteractionEnabled = false
        addSubview(box)

        if let reason {
            let label = UILabel()
            label.text = " \(reason) "
            label.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            label.textColor = .white
            label.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
            label.sizeToFit()
            label.frame.origin = CGPoint(x: 0, y: -label.frame.height)
            box.addSubview(label)
        }

        UIView.animate(withDuration: 0.25, delay: 0.6, options: []) {
            box.alpha = 0
        } completion: { _ in
            box.removeFromSuperview()
        }
    }

    @objc private func stripLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onToggleARDebugOptions?()
    }
}
