import UIKit
import simd

/// 접이식 레이더 미니맵 (FR-111).
///
/// 접힘도 정적 아이콘이 아니라 **라이브 축소판**이다 — 나(중심)·관측 기둥·목표 불확실성만 그린다.
/// 백분율이 "수치의 상승"을 말한다면 이 뷰는 "공간의 수렴"을 보여준다:
/// 한 축만 서면 목표가 띠로, 두 축이 서면 원으로, 관측이 쌓일수록 원이 조여든다.
/// 펼치면 같은 그림이 커지면서 코드 라벨·거리 눈금·이동 자취가 붙는다(다른 화면이 아니라 같은 지도의 확대).
final class ParkingMinimapView: UIView {

    private(set) var isExpanded = false
    private var snapshot: ParkingARViewModel.MinimapSnapshot?

    /// 화면에 그릴 반경(m) — 목표와 관측이 모두 들어오도록 자동 축척
    private var scaleRadius: Double = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        isOpaque = false
        accessibilityLabel = "주변 기둥 지도"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        accessibilityHint = expanded ? "탭하면 접습니다" : "탭하면 펼칩니다"
        setNeedsDisplay()
    }

    func update(_ snapshot: ParkingARViewModel.MinimapSnapshot?) {
        self.snapshot = snapshot
        if let snapshot {
            layer.borderColor = Self.confidenceColor(snapshot.confidencePercent)
                .withAlphaComponent(0.85).cgColor
            scaleRadius = Self.autoScale(snapshot)
            accessibilityValue = snapshot.target == nil
                ? "목표 위치 추정 전"
                : "정확도 \(snapshot.confidencePercent)퍼센트, 기둥 \(snapshot.signs.count)개"
        } else {
            accessibilityValue = nil
        }
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let snapshot else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pixelsPerMeter = Double(min(rect.width, rect.height) / 2 - 6) / max(scaleRadius, 1)

        // 진행 방향이 위 — AR 화살표와 회전 감각을 맞춘다(heading-up)
        let forward = snapshot.forward
        func project(_ world: SIMD2<Double>) -> CGPoint {
            let delta = world - snapshot.device
            // 전방을 위(-y)로 보내는 **순수 회전**. 측방 부호는 GuidanceGeometry의 화살표 규약
            // (전방 기준 시계방향 +)과 같아야 한다 — 반대로 쓰면 행렬식이 -1(거울 반사)이 되어
            // 화살표는 오른쪽, 미니맵은 왼쪽을 가리킨다(PR#61 리뷰에서 실측 확인).
            let x = forward.x * delta.y - forward.y * delta.x
            let y = delta.x * forward.x + delta.y * forward.y
            return CGPoint(x: center.x + CGFloat(x * pixelsPerMeter),
                           y: center.y - CGFloat(y * pixelsPerMeter))
        }

        if isExpanded {
            drawRangeRings(context, center: center, pixelsPerMeter: pixelsPerMeter)
            drawTrail(context, snapshot: snapshot, project: project)
        }
        drawTarget(context, snapshot: snapshot, pixelsPerMeter: pixelsPerMeter, project: project)
        drawSigns(context, snapshot: snapshot, project: project)
        drawDevice(context, center: center)
        if isExpanded { drawScaleLabel(rect) }
    }

    private func drawRangeRings(_ context: CGContext, center: CGPoint, pixelsPerMeter: Double) {
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(1)
        for meters in stride(from: 10.0, through: scaleRadius, by: 10.0) {
            let radius = CGFloat(meters * pixelsPerMeter)
            context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2))
        }
    }

    private func drawTrail(_ context: CGContext, snapshot: ParkingARViewModel.MinimapSnapshot,
                           project: (SIMD2<Double>) -> CGPoint) {
        guard snapshot.trail.count >= 2 else { return }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.25).cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.beginPath()
        context.move(to: project(snapshot.trail[0]))
        for point in snapshot.trail.dropFirst() { context.addLine(to: project(point)) }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    /// 목표 — 미지 축이 남아 있으면 **띠**, 두 축이 서면 **원**. 관측이 쌓일수록 좁아진다.
    private func drawTarget(_ context: CGContext, snapshot: ParkingARViewModel.MinimapSnapshot,
                            pixelsPerMeter: Double, project: (SIMD2<Double>) -> CGPoint) {
        guard let target = snapshot.target else { return }
        let color = Self.confidenceColor(snapshot.confidencePercent)
        let point = project(target)

        if let band = snapshot.uncertaintyBand {
            // 띠: 미지 축 방향으로 ±length, 수직으로 ±radius
            let thickness = CGFloat(max(snapshot.uncertaintyRadius, 0.8) * pixelsPerMeter)
            let end1 = project(target + band.direction * band.length)
            let end2 = project(target - band.direction * band.length)
            context.saveGState()
            context.setStrokeColor(color.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(max(4, thickness * 2))
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: end1)
            context.addLine(to: end2)
            context.strokePath()
            context.restoreGState()
        } else {
            let radius = CGFloat(max(snapshot.uncertaintyRadius, 0.8) * pixelsPerMeter)
            context.setFillColor(color.withAlphaComponent(0.28).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                           width: radius * 2, height: radius * 2))
        }

        // 목표 중심 — 클램프해서 원 밖으로 나가지 않게
        let clamped = clampToBounds(point)
        context.setFillColor(color.cgColor)
        let size: CGFloat = isExpanded ? 9 : 6
        context.fillEllipse(in: CGRect(x: clamped.x - size / 2, y: clamped.y - size / 2,
                                       width: size, height: size))
    }

    private func drawSigns(_ context: CGContext, snapshot: ParkingARViewModel.MinimapSnapshot,
                           project: (SIMD2<Double>) -> CGPoint) {
        for sign in snapshot.signs {
            let point = project(sign.position)
            guard bounds.insetBy(dx: -8, dy: -8).contains(point) else { continue }
            // 오래된 관측일수록 흐리게 — 불확실성 팽창(FR-108)이 눈에 보이게
            let freshness = max(0.25, 1.0 - sign.ageSeconds / 60.0)
            let alpha = CGFloat(sign.isChosen ? freshness : freshness * 0.5)
            context.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            let size: CGFloat = sign.isChosen ? 5 : 3.5
            context.fillEllipse(in: CGRect(x: point.x - size / 2, y: point.y - size / 2,
                                           width: size, height: size))
            guard isExpanded else { continue }
            // 다중 표지판은 제외된 게 아니라 나뉘어 있음을 라벨로 드러낸다
            let label = sign.isMultiSign ? "\(sign.code)·" : sign.code
            (label as NSString).draw(
                at: CGPoint(x: point.x + 5, y: point.y - 6),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(alpha),
                ]
            )
        }
    }

    private func drawDevice(_ context: CGContext, center: CGPoint) {
        // 시야 쐐기 — 지금 비추는 범위
        context.setFillColor(UIColor.white.withAlphaComponent(0.12).cgColor)
        let reach: CGFloat = isExpanded ? 34 : 18
        context.beginPath()
        context.move(to: center)
        context.addLine(to: CGPoint(x: center.x - reach * 0.45, y: center.y - reach))
        context.addLine(to: CGPoint(x: center.x + reach * 0.45, y: center.y - reach))
        context.closePath()
        context.fillPath()

        context.setFillColor(Theme.Colors.accent.cgColor)
        let size: CGFloat = isExpanded ? 8 : 6
        context.fillEllipse(in: CGRect(x: center.x - size / 2, y: center.y - size / 2,
                                       width: size, height: size))
    }

    private func drawScaleLabel(_ rect: CGRect) {
        let text = "반경 \(Int(scaleRadius.rounded()))m" as NSString
        text.draw(
            at: CGPoint(x: 10, y: rect.height - 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            ]
        )
    }

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let limit = min(bounds.width, bounds.height) / 2 - 8
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > limit, distance > 0 else { return point }
        let ratio = limit / distance
        return CGPoint(x: center.x + dx * ratio, y: center.y + dy * ratio)
    }

    // MARK: - Helpers

    /// 목표와 관측이 모두 들어오는 반경 — 목표가 아주 멀면 가장자리 클램프에 맡긴다
    private static func autoScale(_ snapshot: ParkingARViewModel.MinimapSnapshot) -> Double {
        // 축척 기준은 **관측 배치**다. 멀리 있는 목표까지 축척에 넣으면 0.4px/m가 되어
        // 정작 주변 기둥이 중앙에 뭉개진다 — 먼 목표는 가장자리 클램프가 표현한다(PR#61 리뷰)
        var maximum = 8.0
        for sign in snapshot.signs {
            maximum = max(maximum, simd_distance(sign.position, snapshot.device))
        }
        if let target = snapshot.target {
            // 목표가 관측 범위 안이면 포함, 밖이면 관측 기준 유지
            maximum = max(maximum, min(simd_distance(target, snapshot.device), maximum * 1.4))
        }
        return min(maximum * 1.15, 40)
    }

    /// 정확도 색 — 화살표·게이지와 같은 체계 (Theme 토큰 경유, constitution 디자인 토큰 조항)
    private static func confidenceColor(_ percent: Int) -> UIColor {
        if percent >= ParkingTuning.confidencePercentTopThreshold { return Theme.Colors.success }
        if percent >= ParkingTuning.confidencePercentSolidThreshold { return .systemYellow }   // Theme에 warning 토큰 없음
        return .systemGray
    }
}
