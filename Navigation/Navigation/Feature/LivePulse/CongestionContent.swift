import UIKit
import SwiftUI
import CoreLocation

/// 마커 탭 상세 — 핀 인사이트 팝업(`MapItemContent`)에 끼워 넣는 실시간 혼잡 카드.
/// place(=가벼운 _ppltn 데이터)로 먼저 그리고, 풀 citydata(detail) 도착 시 rootView 재할당.
final class CongestionContent: MapItemContent {

    let place: CongestionPlace
    private let hosting: UIHostingController<CongestionDetailView>

    init(place: CongestionPlace) {
        self.place = place
        hosting = UIHostingController(rootView: CongestionDetailView(place: place, detail: nil, loading: true))
        hosting.view.backgroundColor = .clear
    }

    /// 풀 citydata 도착 반영
    func setDetail(_ detail: CitydataDetail?) {
        hosting.rootView = CongestionDetailView(place: place, detail: detail, loading: false)
    }

    // MARK: - MapItemContent
    var iconImage: UIImage? { UIImage(systemName: "waveform.path.ecg") }
    var title: String { place.areaName }
    var identifier: String { "congestion-\(place.areaName)" }
    var contentView: UIView { hosting.view }
    var footerActions: [MapItemAction] { [] }
}

// MARK: - SwiftUI Card

struct CongestionDetailView: View {
    let place: CongestionPlace
    let detail: CitydataDetail?
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            congestionHeader
            Divider()
            populationSection
            forecastSection
            weatherSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // 혼잡 + 인구 + 기준시각
    private var congestionHeader: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(place.liveLevel.markerColor)).frame(width: 12, height: 12)
            Text(place.liveLevel.displayName).font(.headline)
            if let p = populationText { Text(p).font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            Text("기준 \(shortTime(place.baseTime))").font(.caption).foregroundStyle(.secondary)
        }
    }

    // 성별 / 연령 / 상주·방문
    @ViewBuilder private var populationSection: some View {
        if let ppl = detail?.population {
            VStack(alignment: .leading, spacing: 6) {
                if let m = ppl.maleRate, let f = ppl.femaleRate {
                    row("성별", "남 \(pct(m)) · 여 \(pct(f))")
                }
                let ages = ppl.ageBreakdown.prefix(3)
                if !ages.isEmpty {
                    row("연령", ages.map { "\($0.label) \(Int($0.rate))%" }.joined(separator: " · "))
                }
                if let r = ppl.resntRate, let n = ppl.nonResntRate {
                    row("구성", "상주 \(pct(r)) · 방문 \(pct(n))")
                }
            }
        } else if loading {
            row("인구", "불러오는 중…")
        }
    }

    // 12시간 예측 (간단 색 띠)
    @ViewBuilder private var forecastSection: some View {
        if !place.forecast.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("12시간 예측").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(Array(place.forecast.prefix(12).enumerated()), id: \.offset) { _, f in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(f.level.markerColor))
                            .frame(height: 14)
                    }
                }
            }
        }
    }

    // 날씨 / 대기 / UV / 주차 / 따릉이
    @ViewBuilder private var weatherSection: some View {
        if let w = detail?.weather {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                row("날씨", [
                    w.temp.map { "\($0)°" },
                    pcp(w),
                    w.pm10Index.map { "미세먼지 \($0)" },
                    w.uvIndex.map { "UV \($0)" },
                ].compactMap { $0 }.joined(separator: " · "))
                if let d = detail {
                    row("주변", "주차장 \(d.parkingLotCount)곳 · 따릉이 \(d.bikeAvailable)대")
                }
            }
        }
    }

    // MARK: - Helpers
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer(minLength: 0)
        }
    }
    private var populationText: String? {
        guard let mn = place.pplMin, let mx = place.pplMax else { return nil }
        return "\(comma(mn))~\(comma(mx))명"
    }
    private func pcp(_ w: CitydataDetail.Weather) -> String? {
        if let p = w.precipitation, p != "-", !p.isEmpty { return "강수 \(p)mm" }
        return "강수 없음"
    }
    private func pct(_ s: String) -> String { (Double(s).map { String(format: "%.0f%%", $0) }) ?? "\(s)%" }
    private func comma(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    private func shortTime(_ s: String) -> String { String(s.suffix(5)) } // "HH:mm"
}
