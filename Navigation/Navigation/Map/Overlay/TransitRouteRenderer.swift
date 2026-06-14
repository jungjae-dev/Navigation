import MapKit
import UIKit

/// 대중교통 노선 폴리라인 렌더러
/// - 선택 정류소가 포함된 방향(primary)은 짙은 색·굵게, 반대 방향은 옅은 색·얇게
/// - 노선을 따라 진행 방향(seq 증가 방향) 화살표(셰브론)를 일정 간격으로 그림
final class TransitRouteRenderer: MKPolylineRenderer {

    private let isPrimary: Bool

    /// 노선 기본 색 (#3366CC — 버스 정류장 마커와 동일 톤)
    private static let routeColor = UIColor(red: 0x33 / 255, green: 0x66 / 255, blue: 0xCC / 255, alpha: 1)

    /// 화살표 사이 화면상 간격(pt)
    private static let arrowScreenSpacing: CGFloat = 90
    /// 화살표 팔 길이 화면상 크기(pt)
    private static let arrowScreenArm: CGFloat = 6

    nonisolated init(polyline: MKPolyline, isPrimary: Bool) {
        self.isPrimary = isPrimary
        super.init(polyline: polyline)
        MainActor.assumeIsolated {
            strokeColor = isPrimary
                ? Self.routeColor.withAlphaComponent(0.9)
                : Self.routeColor.withAlphaComponent(0.45)
            lineWidth = isPrimary ? 5.0 : 3.0
            lineCap = .round
            lineJoin = .round
        }
    }

    nonisolated override init(overlay: any MKOverlay) {
        self.isPrimary = false
        super.init(overlay: overlay)
    }

    nonisolated override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // 노선 선
        super.draw(mapRect, zoomScale: zoomScale, in: context)

        let line = polyline
        let count = line.pointCount
        guard count >= 2, zoomScale > 0 else { return }
        let points = line.points()

        // 화면상 일정 간격을 맵 좌표 단위로 환산 (맵단위 * zoomScale = 화면 pt)
        let step = Double(Self.arrowScreenSpacing) / Double(zoomScale)
        let arm = Double(Self.arrowScreenArm) / Double(zoomScale)
        guard step > 0 else { return }

        let arrowColor = UIColor.white.withAlphaComponent(isPrimary ? 0.95 : 0.5)
        context.saveGState()
        context.setStrokeColor(arrowColor.cgColor)
        context.setLineWidth(Double(isPrimary ? 2.2 : 1.6) / Double(zoomScale))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // 첫 화살표는 한 스텝 진행 후부터 배치
        var distanceToNext = step
        for i in 0..<(count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let segLen = (dx * dx + dy * dy).squareRoot()
            guard segLen > 0 else { continue }
            let ux = dx / segLen
            let uy = dy / segLen

            var traveled = 0.0
            while distanceToNext <= segLen - traveled {
                traveled += distanceToNext
                distanceToNext = step
                let cx = a.x + ux * traveled
                let cy = a.y + uy * traveled
                addChevron(center: MKMapPoint(x: cx, y: cy), ux: ux, uy: uy, arm: arm, into: context)
            }
            distanceToNext -= (segLen - traveled)
        }

        context.strokePath()
        context.restoreGState()
    }

    /// 진행 방향(ux,uy)을 향하는 ">" 형태 셰브론을 path에 추가
    private nonisolated func addChevron(center: MKMapPoint, ux: Double, uy: Double, arm: Double, into context: CGContext) {
        let px = -uy  // 수직 방향
        let py = ux
        let tip = MKMapPoint(x: center.x + ux * arm, y: center.y + uy * arm)
        let back = MKMapPoint(x: center.x - ux * arm, y: center.y - uy * arm)
        let left = MKMapPoint(x: back.x + px * arm, y: back.y + py * arm)
        let right = MKMapPoint(x: back.x - px * arm, y: back.y - py * arm)

        let tipP = point(for: tip)
        context.move(to: point(for: left))
        context.addLine(to: tipP)
        context.move(to: point(for: right))
        context.addLine(to: tipP)
    }
}
