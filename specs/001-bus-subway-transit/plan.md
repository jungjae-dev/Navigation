# Implementation Plan: 버스/지하철 대중교통 기능

**Branch**: `001-bus-subway-transit` | **Date**: 2026-06-03 | **Spec**: [spec.md](./spec.md)

## Summary

서울 버스/지하철 정류장·역 마커를 지도에 표시하고, 실시간 도착·노선·시간표를 제공하는 기능을 추가한다. 기존 따릉이 레이어와 동일한 패턴(POI 팝업 → Annotation → ViewModel)으로 구현하며, 정적 데이터는 GitHub Gist에서 버전 관리한다.

## Technical Context

**Language/Version**: Swift 6, iOS 26

**Primary Dependencies**: UIKit (programmatic), MapKit, Combine, Firebase RemoteConfig

**Storage**: Documents/TransitData/ (다운로드 캐시), 번들 fallback JSON

**Testing**: Swift Testing (`import Testing`, `#expect`, `@Test`)

**Target Platform**: iOS 26, iPhone + CarPlay (CarPlay는 이 feature 범위 외)

**Project Type**: iOS mobile app (MVVM + Coordinator + Combine)

**Performance Goals**: 마커 표시 3초 이내, 실시간 도착 조회 5초 이내

**Constraints**: Swift 6 strict concurrency, MainActor 기본 격리, 오프라인 동작 필수

**Scale/Scope**: 버스 정류장 11,250개, 지하철역 276개, 1~8호선

## Constitution Check

| 원칙 | 상태 | 비고 |
|------|------|------|
| Swift 6 Concurrency | ✅ | nonisolated + MainActor.assumeIsolated 패턴 적용 |
| MVVM + Coordinator + Combine | ✅ | 기존 Bike 패턴 재사용, CurrentValueSubject 사용 |
| 단순성 우선 | ✅ | 추측 기반 추상화 없음, 기존 SeoulAPIClient 재사용 |
| 로그 기반 검증 | ✅ | 각 Phase Logger 포인트 정의 |
| iOS 26 API | ✅ | MKMapItem(location:address:) 사용 |
| pbxproj 수동 참조 금지 | ✅ | auto-sync 폴더에 파일 추가 |

## Project Structure

### Documentation (this feature)

```text
specs/001-bus-subway-transit/
├── plan.md              ← 이 파일
├── research.md          ← Phase 0 출력
├── data-model.md        ← Phase 1 출력
├── contracts/           ← Phase 1 출력
└── tasks.md             ← /speckit-tasks 출력
```

### Source Code

```text
Navigation/Navigation/Navigation/
├── Service/
│   ├── SeoulOpenAPI/          (기존)
│   │   ├── Bike/
│   │   ├── Bus/               ← 신규
│   │   │   └── BusAPIClient.swift
│   │   └── Subway/            ← 신규
│   │       ├── SubwayAPIClient.swift
│   │       └── SubwayTimetableAPI.swift
│   └── Transit/               ← 신규
│       ├── TransitDataService.swift
│       ├── TransitGistURLs.swift
│       └── TransitModel.swift
├── Feature/
│   ├── Bike/                  (기존 참조)
│   ├── MapItemDetail/
│   │   └── Content/
│   │       ├── BusStopContent.swift      ← 신규
│   │       ├── BusStopContentView.swift  ← 신규
│   │       ├── SubwayStationContent.swift ← 신규
│   │       └── SubwayStationContentView.swift ← 신규
│   ├── Transit/               ← 신규
│   │   ├── BusViewModel.swift
│   │   ├── SubwayViewModel.swift
│   │   ├── BusRouteDrawerViewController.swift
│   │   ├── BusStopTimetableDrawerViewController.swift
│   │   ├── SubwayLineDrawerViewController.swift
│   │   └── SubwayStationTimetableDrawerViewController.swift
│   ├── Home/
│   │   ├── HomeViewController.swift      (수정: POI 팝업)
│   │   ├── HomeViewModel.swift
│   │   └── MapControlButtonsView.swift   (수정: POI 레이어 버튼)
│   └── Settings/              (수정: 데이터 갱신 섹션 추가)
└── Map/
    └── Annotation/
        ├── BusStopAnnotation.swift        ← 신규
        ├── BusStopAnnotationView.swift    ← 신규
        ├── SubwayStationAnnotation.swift  ← 신규
        └── SubwayStationAnnotationView.swift ← 신규
```

**Structure Decision**: 기존 Bike 패턴과 동일한 계층 구조. SeoulOpenAPI 하위에 Bus/Subway 클라이언트, Feature/Transit에 ViewModel·드로어, Map/Annotation에 마커 추가.

## Implementation Phases

### Phase 1: 데이터 로드 + 지도 마커 (P1)

**목표**: 버스/지하철 마커 지도 표시

**신규 파일**:
- `Service/Transit/TransitGistURLs.swift` — URL 상수
- `Service/Transit/TransitModel.swift` — BusStop, SubwayStation, SubwayLines, TransitDataVersion
- `Service/Transit/TransitDataService.swift` — version.json 체크 → 다운로드 → 캐시
- `Map/Annotation/BusStopAnnotation.swift` + `BusStopAnnotationView.swift`
- `Map/Annotation/SubwayStationAnnotation.swift` + `SubwayStationAnnotationView.swift`
- `Feature/Transit/BusViewModel.swift`
- `Feature/Transit/SubwayViewModel.swift`

**수정 파일**:
- `Feature/Home/MapControlButtonsView.swift` — 따릉이 토글 → POI 팝업 버튼으로 교체
- `Feature/Home/HomeViewController.swift` — POI 팝업 + 버스/지하철 마커 연동
- `MapViewController` — setBusStops/setSubwayStations/clear 메서드 추가

**검증 로그**:
```swift
Logger.transit.info("version.json fetched: busStops=\(busVer), stations=\(stationVer)")
Logger.transit.info("bus_stops downloaded: \(count) stops")
Logger.transit.info("subway_stations downloaded: \(count) stations")
Logger.transit.info("Using cached bus_stops (version up to date)")
Logger.transit.warning("Gist fetch failed, using bundle fallback")
```

---

### Phase 2: 버스 정류소 상세 + 실시간 도착 (P2)

**목표**: 마커 탭 → 실시간 도착 시트

**신규 파일**:
- `Service/SeoulOpenAPI/Bus/BusAPIClient.swift`
- `Feature/MapItemDetail/Content/BusStopContent.swift` + `BusStopContentView.swift`

**수정 파일**:
- `Coordinator/AppCoordinator.swift` — showBusStopDetail, showBusRoute, showBusStopTimetable

---

### Phase 3: 버스 노선 상세 (P3)

**목표**: 노선 탭 → 폴리라인 + 정류소 드로어

**신규 파일**:
- `Feature/Transit/BusRouteDrawerViewController.swift`

**수정 파일**:
- `BusAPIClient.swift` — fetchRouteStops, fetchRoutePolyline
- `MapViewController` — showBusRoutePolyline, clearTransitPolyline
- `AppCoordinator` — 드로어 스택 1개 제한 로직

---

### Phase 4: 버스 시간표 (P4)

**신규 파일**:
- `Feature/Transit/BusStopTimetableDrawerViewController.swift`

**수정 파일**:
- `BusAPIClient.swift` — fetchTimetable (디스크 캐시)

---

### Phase 5: 지하철역 상세 + 실시간 도착 (P5)

**신규 파일**:
- `Service/SeoulOpenAPI/Subway/SubwayAPIClient.swift`
- `Feature/MapItemDetail/Content/SubwayStationContent.swift` + `SubwayStationContentView.swift`

---

### Phase 6: 지하철 노선 상세 (P6)

**신규 파일**:
- `Feature/Transit/SubwayLineDrawerViewController.swift`

**수정 파일**:
- `MapViewController` — showSubwayLinePolyline (순환선 처리)

---

### Phase 7: 지하철 시간표 (P7)

**신규 파일**:
- `Service/SeoulOpenAPI/Subway/SubwayTimetableAPI.swift`
- `Feature/Transit/SubwayStationTimetableDrawerViewController.swift`

---

### Phase 8: 설정 화면 데이터 갱신 (P8)

**수정 파일**:
- `Feature/Settings/` — 데이터 갱신 섹션 추가 (마지막 갱신 날짜, 하루 1회 제한)
- `TransitDataService.swift` — refreshAll(), canRefreshToday(), clearTimetableCache()
