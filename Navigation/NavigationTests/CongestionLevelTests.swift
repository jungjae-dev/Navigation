import Testing
import CoreLocation
import MapKit
@testable import Navigation

/// 혼잡 단계 파싱 + offset→단계 선택 (FR-002/004/011, citydata 실데이터 표기 기준)
struct CongestionLevelTests {

    // MARK: - 단계 파싱 (T007)

    @Test func parsesAllFourLevels() {
        #expect(CongestionLevel(rawText: "붐빔") == .busy)
        #expect(CongestionLevel(rawText: "약간 붐빔") == .slightlyBusy)  // 공백 변형
        #expect(CongestionLevel(rawText: "보통") == .normal)
        #expect(CongestionLevel(rawText: "여유") == .relaxed)
    }

    @Test func parsesSlightlyBusyWithoutSpace() {
        #expect(CongestionLevel(rawText: "약간붐빔") == .slightlyBusy)
    }

    @Test func unknownForGarbageOrEmpty() {
        #expect(CongestionLevel(rawText: "") == .unknown)
        #expect(CongestionLevel(rawText: "혼잡") == .unknown)
    }

    @Test func unknownIsNotDisplayable() {
        #expect(CongestionLevel.unknown.isDisplayable == false)
        #expect(CongestionLevel.busy.isDisplayable == true)
    }

    @Test func severityOrdering() {
        #expect(CongestionLevel.relaxed.rawValue < CongestionLevel.normal.rawValue)
        #expect(CongestionLevel.normal.rawValue < CongestionLevel.slightlyBusy.rawValue)
        #expect(CongestionLevel.slightlyBusy.rawValue < CongestionLevel.busy.rawValue)
    }

    // MARK: - offset → 단계 선택 (T019)

    private func makePlace(live: CongestionLevel, forecast: [CongestionLevel]) -> CongestionPlace {
        CongestionPlace(
            areaName: "테스트",
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            rings: [],
            liveLevel: live,
            baseTime: "2026-06-26 10:20",
            pplMin: 1000, pplMax: 2000,
            forecast: forecast.enumerated().map {
                CongestionForecastPoint(time: "+\($0.offset + 1)h", level: $0.element, pplMin: nil, pplMax: nil)
            }
        )
    }

    @Test func offsetZeroIsLive() {
        let p = makePlace(live: .busy, forecast: [.normal, .relaxed])
        #expect(p.level(atOffset: 0) == .busy)
    }

    @Test func offsetNIsForecast() {
        let p = makePlace(live: .busy, forecast: [.normal, .relaxed, .slightlyBusy])
        #expect(p.level(atOffset: 1) == .normal)        // forecast[0]
        #expect(p.level(atOffset: 3) == .slightlyBusy)  // forecast[2]
    }

    @Test func offsetBeyondForecastIsUnknown() {
        let p = makePlace(live: .busy, forecast: [.normal])
        #expect(p.level(atOffset: 5) == .unknown)
        #expect(p.forecastCount == 1)
    }

    // MARK: - 카탈로그 가시영역 필터 (FR-007a)

    @Test func catalogFiltersVisibleArea() {
        let cat = HotspotCatalog(hotspots: [
            Hotspot(areaName: "강남역", areaCode: "POI014", category: "인구밀집지역", center: [37.49795, 127.02762], rings: []),
            Hotspot(areaName: "광화문·덕수궁", areaCode: "POI009", category: "고궁·문화유산", center: [37.571, 126.9769], rings: []),
        ])
        // 전 세계 영역 → 모두 포함
        #expect(cat.visibleAreaNames(in: MKMapRect.world).count == 2)

        // 강남역 좌표를 감싸는 작은 영역 → 강남역만 (광화문 제외)
        let p = MKMapPoint(CLLocationCoordinate2D(latitude: 37.49795, longitude: 127.02762))
        let around = MKMapRect(x: p.x - 5_000, y: p.y - 5_000, width: 10_000, height: 10_000)
        let names = cat.visibleAreaNames(in: around)
        #expect(names == ["강남역"])
    }
}
