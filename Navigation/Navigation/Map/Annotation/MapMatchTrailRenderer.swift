import UIKit
import MapKit

/// MapMatchTrailOverlay 의 모든 entry 를 단일 CGContext 에 그림.
///
/// 시각 요소:
/// - GPS 점: 빨간 원 + 빨간 화살표(heading 방향)
/// - 매칭 점: 파란 원 + 파란 화살표
/// - 두 점 잇는 흰 점선
///
/// 화면 픽셀 기준 크기를 zoomScale 로 보정하여 줌 레벨과 무관하게 일정 크기로 표시.
final class MapMatchTrailRenderer: MKOverlayRenderer {

    // MARK: - Style (screen pixels)

    /// GPS 점 — 작은 빨간 링 (속이 빈 원)
    private let gpsRingRadius: CGFloat = 5
    /// 매칭 점 — 큰 녹색 링 (경로와 겹쳐도 잘 보이는 색)
    private let matchedRingRadius: CGFloat = 9
    private let ringLineWidth: CGFloat = 2

    private let arrowLength: CGFloat = 18
    private let arrowLineWidth: CGFloat = 2.5
    private let arrowHeadSize: CGFloat = 6
    private let linkLineWidth: CGFloat = 1.5
    private let linkDashPattern: [CGFloat] = [4, 3]

    // MARK: - Draw

    override func draw(
        _ mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        guard let trail = overlay as? MapMatchTrailOverlay else { return }
        let entries = trail.snapshotEntries()
        guard !entries.isEmpty else { return }

        // 줌과 무관한 일정 시각 크기를 위해 모든 길이를 zoomScale 로 나눔
        let inv = 1.0 / Double(zoomScale)
        let gpsR = CGFloat(Double(gpsRingRadius) * inv)
        let matchedR = CGFloat(Double(matchedRingRadius) * inv)
        let ringLW = CGFloat(Double(ringLineWidth) * inv)
        let arrowL = CGFloat(Double(arrowLength) * inv)
        let arrowLW = CGFloat(Double(arrowLineWidth) * inv)
        let arrowHead = CGFloat(Double(arrowHeadSize) * inv)
        let linkLW = CGFloat(Double(linkLineWidth) * inv)
        let linkDash = linkDashPattern.map { CGFloat(Double($0) * inv) }

        // visible rect 보정 (점·화살표가 일부 걸치는 경우도 포함하도록 마진)
        let margin = max(arrowL, max(gpsR, matchedR)) * 2
        let cullRect = mapRect.insetBy(dx: -Double(margin), dy: -Double(margin))

        let red = UIColor.systemRed.cgColor
        let green = UIColor.systemGreen.cgColor
        let white = UIColor.white.withAlphaComponent(0.95).cgColor

        // 1) 링크(점선) — 가장 아래 레이어
        context.setStrokeColor(white)
        context.setLineWidth(linkLW)
        context.setLineDash(phase: 0, lengths: linkDash)
        for entry in entries {
            guard let matched = entry.matchedCoord else { continue }
            let gpsMP = MKMapPoint(entry.gpsCoord)
            let matchedMP = MKMapPoint(matched)
            // 둘 중 하나라도 visible rect 안이면 그림
            if !cullRect.contains(gpsMP) && !cullRect.contains(matchedMP) { continue }
            let p1 = point(for: gpsMP)
            let p2 = point(for: matchedMP)
            context.move(to: p1)
            context.addLine(to: p2)
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        // 2) GPS 화살표 + 작은 빨간 링
        for entry in entries {
            let mp = MKMapPoint(entry.gpsCoord)
            guard cullRect.contains(mp) else { continue }
            let pt = point(for: mp)
            drawArrow(
                ctx: context, center: pt, headingDeg: entry.gpsHeading,
                length: arrowL, lineWidth: arrowLW, headSize: arrowHead, color: red
            )
            drawRing(ctx: context, center: pt, radius: gpsR, lineWidth: ringLW, stroke: red)
        }

        // 3) 매칭 화살표 + 큰 녹색 링
        for entry in entries {
            guard let coord = entry.matchedCoord else { continue }
            let mp = MKMapPoint(coord)
            guard cullRect.contains(mp) else { continue }
            let pt = point(for: mp)
            if let heading = entry.matchedHeading {
                drawArrow(
                    ctx: context, center: pt, headingDeg: heading,
                    length: arrowL, lineWidth: arrowLW, headSize: arrowHead, color: green
                )
            }
            drawRing(ctx: context, center: pt, radius: matchedR, lineWidth: ringLW, stroke: green)
        }
    }

    // MARK: - Drawing primitives

    /// 속이 빈 링 (테두리만). 두 종류 점이 겹쳐도 안쪽이 보임.
    private func drawRing(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        stroke: CGColor
    ) {
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        ctx.setStrokeColor(stroke)
        ctx.setLineWidth(lineWidth)
        ctx.strokeEllipse(in: rect)
    }

    /// MKMapPoint 좌표계: y가 남쪽으로 증가 → heading 0(북) 은 -y 방향
    private func drawArrow(
        ctx: CGContext,
        center: CGPoint,
        headingDeg: CLLocationDirection,
        length: CGFloat,
        lineWidth: CGFloat,
        headSize: CGFloat,
        color: CGColor
    ) {
        guard headingDeg.isFinite, headingDeg >= 0 else { return }
        let rad = headingDeg * .pi / 180.0
        let dx = sin(rad)
        let dy = -cos(rad)

        let tip = CGPoint(
            x: center.x + CGFloat(dx) * length,
            y: center.y + CGFloat(dy) * length
        )

        // 본체
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: center)
        ctx.addLine(to: tip)
        ctx.strokePath()

        // 화살촉 (V)
        let leftAngle = rad + .pi - .pi / 6
        let rightAngle = rad + .pi + .pi / 6
        let leftPoint = CGPoint(
            x: tip.x + CGFloat(sin(leftAngle)) * headSize,
            y: tip.y - CGFloat(cos(leftAngle)) * headSize
        )
        let rightPoint = CGPoint(
            x: tip.x + CGFloat(sin(rightAngle)) * headSize,
            y: tip.y - CGFloat(cos(rightAngle)) * headSize
        )
        ctx.setFillColor(color)
        ctx.beginPath()
        ctx.move(to: tip)
        ctx.addLine(to: leftPoint)
        ctx.addLine(to: rightPoint)
        ctx.closePath()
        ctx.fillPath()
    }
}
