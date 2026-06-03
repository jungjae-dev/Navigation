# Tasks: 버스/지하철 대중교통 기능

**Input**: `specs/001-bus-subway-transit/` (plan.md, spec.md, research.md, data-model.md)

**Branch**: `001-bus-subway-transit`

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 병렬 실행 가능 (다른 파일, 의존성 없음)
- **[Story]**: 해당 User Story (US1~US8)

---

## Phase 1: Setup (공유 인프라)

**Purpose**: 데이터 모델, URL 상수, 서비스 기반 구성

- [x] T001 `Navigation/Navigation/Navigation/Service/Transit/` 디렉토리 생성
- [x] T002 [P] `Navigation/Navigation/Navigation/Service/SeoulOpenAPI/Bus/` 디렉토리 생성
- [x] T003 [P] `Navigation/Navigation/Navigation/Service/SeoulOpenAPI/Subway/` 디렉토리 생성
- [x] T004 [P] `Navigation/Navigation/Navigation/Feature/Transit/` 디렉토리 생성
- [x] T005 `Navigation/Navigation/Navigation/Service/Transit/TransitGistURLs.swift` 생성 — Gist Raw URL 4개 상수 정의
- [x] T006 `Navigation/Navigation/Navigation/Service/Transit/TransitModel.swift` 생성 — BusStop, SubwayStation, SubwayLines, TransitDataVersion, TransitDataState 모델

**Checkpoint**: 모델과 URL 상수 준비 완료 — 이후 모든 Phase가 이 파일에 의존

---

## Phase 2: Foundational (모든 User Story 전제조건)

**Purpose**: TransitDataService — 데이터 다운로드 및 캐시 (US1~US8 전체 의존)

**⚠️ CRITICAL**: 이 Phase 완료 전에는 어떤 User Story도 시작 불가

- [x] T007 `Navigation/Navigation/Navigation/Service/Transit/TransitDataService.swift` 생성 — version.json fetch → 버전 비교 → 변경 파일만 다운로드 → Documents/TransitData/ 저장
- [x] T008 `TransitDataService.swift` 수정 — 번들 fallback 로직 추가 (네트워크 없을 때 번들 JSON 사용)
- [x] T009 [P] `TransitDataService.swift` 수정 — refreshAll(), canRefreshToday(), clearTimetableCache() 메서드 추가

**검증 로그**:
```
Logger.transit.info("version.json fetched: busStops=\(busVer)")
Logger.transit.info("bus_stops downloaded: \(count) stops")
Logger.transit.info("Using cached bus_stops (version up to date)")
Logger.transit.warning("Gist fetch failed, using bundle fallback")
```

**Checkpoint**: 앱 시작 시 버스/지하철 데이터가 로컬에 캐시됨 — 이후 User Story 시작 가능

---

## Phase 3: User Story 1 - 지도 마커 표시 (Priority: P1) 🎯 MVP

**Goal**: POI 팝업에서 버스/지하철 레이어 ON/OFF → 지도에 마커 표시

**Independent Test**: 앱 실행 → POI 버튼 탭 → 버스 ON → 지도에 정류장 마커 표시 확인 (로그: `bus_stops downloaded: 11250 stops`)

### Implementation for User Story 1

- [x] T010 [US1] `Navigation/Navigation/Navigation/Map/Annotation/BusStopAnnotation.swift` 생성 — MKPointAnnotation 서브클래스, BusStop 참조
- [x] T011 [P] [US1] `Navigation/Navigation/Navigation/Map/Annotation/BusStopAnnotationView.swift` 생성 — 버스 색상 마커 뷰
- [x] T012 [P] [US1] `Navigation/Navigation/Navigation/Map/Annotation/SubwayStationAnnotation.swift` 생성 — SubwayStation 참조, 호선 색상 포함
- [x] T013 [P] [US1] `Navigation/Navigation/Navigation/Map/Annotation/SubwayStationAnnotationView.swift` 생성 — 환승역 복합 색상 마커 뷰
- [x] T014 [US1] `Navigation/Navigation/Navigation/Feature/Transit/BusViewModel.swift` 생성 — isLayerOn: Bool, toggleLayer(), TransitDataService 구독
- [x] T015 [P] [US1] `Navigation/Navigation/Navigation/Feature/Transit/SubwayViewModel.swift` 생성 — isLayerOn: Bool, toggleLayer(), TransitDataService 구독
- [x] T016 [US1] `Navigation/Navigation/Navigation/Feature/Home/MapControlButtonsView.swift` 수정 — 따릉이 단독 토글 제거, POI 레이어 팝업 버튼 추가 (따릉이/버스/지하철 토글)
- [x] T017 [US1] `Navigation/Navigation/Navigation/Feature/Home/HomeViewController.swift` 수정 — POI 팝업 연동, 버스/지하철 ViewModel 초기화, 줌 레벨 기반 마커 표시/숨김 (버스 latΔ≤0.03, 지하철 latΔ≤0.15)
- [x] T018 [US1] `MapViewController` 수정 — setBusStops([BusStop]), setSubwayStations([SubwayStation]), clearBusStops(), clearSubwayStations() 메서드 추가

**Checkpoint**: POI 팝업에서 버스/지하철 ON → 지도 마커 표시. 오프라인에서도 번들 fallback으로 동작.

---

## Phase 4: User Story 2 - 버스 정류소 상세 + 실시간 도착 (Priority: P2)

**Goal**: 버스 마커 탭 → 경유 노선 목록 + 실시간 도착 정보 시트

**Independent Test**: 버스 마커 탭 → 시트 열림 → 로그: `Arrivals fetched: N routes` 확인

### Implementation for User Story 2

- [x] T019 [US2] `Navigation/Navigation/Navigation/Service/SeoulOpenAPI/Bus/BusAPIClient.swift` 생성 — ws.bus.go.kr 클라이언트, BUS_API_KEY, getStationByUid(arsId:) 메서드
- [x] T020 [US2] `Navigation/Navigation/Navigation/Feature/MapItemDetail/Content/BusStopContent.swift` 생성 — MapItemContent 프로토콜 구현, 노선별 도착 정보 + 새로고침 버튼 + 시간표/도보 버튼
- [x] T021 [US2] `Navigation/Navigation/Navigation/Feature/MapItemDetail/Content/BusStopContentView.swift` 생성 — 노선별 도착 정보 UI
- [x] T022 [US2] `Coordinator/AppCoordinator.swift` 수정 — showBusStopDetail(_:), onRouteTapped, onWalkingRoute 콜백 연결

**Checkpoint**: 버스 마커 탭 → 경유 노선 + 실시간 도착 표시. 새로고침 동작.

---

## Phase 5: User Story 3 - 버스 노선 상세 (Priority: P3)

**Goal**: 노선 탭 → 지도 폴리라인 + 경유 정류소 드로어

**Independent Test**: 노선 탭 → 로그: `Route stops fetched: N stops` + 지도에 폴리라인 표시

### Implementation for User Story 3

- [x] T023 [US3] `BusAPIClient.swift` 수정 — fetchRouteStops(routeId:), fetchRoutePolyline(routeId:), 인메모리 캐시 추가
- [x] T024 [US3] `Navigation/Navigation/Navigation/Feature/Transit/BusRouteDrawerViewController.swift` 생성 — 노선명/기종점 헤더, 정류소 목록 (현재 정류소 강조), 정류소 탭 → 지도 카메라 이동
- [x] T025 [US3] `MapViewController` 수정 — showBusRoutePolyline(_:color:), clearTransitPolyline() 추가
- [x] T026 [US3] `AppCoordinator.swift` 수정 — showBusRoute(routeId:from:stop:), 드로어 스택 1개 제한 (정류소 상세 1개 + 노선 1개)

**Checkpoint**: 노선 탭 → 폴리라인 + 정류소 드로어. 지도 다른 마커 탭 시 노선 드로어 닫힘.

---

## Phase 6: User Story 4 - 버스 시간표 (Priority: P4)

**Goal**: 시간표 버튼 탭 → 노선/요일별 시간 그리드

**Independent Test**: 시간표 버튼 탭 → 로그: `Timetable fetched: N entries` (재조회 시 `Timetable cache hit`)

### Implementation for User Story 4

- [x] T027 [US4] `BusAPIClient.swift` 수정 — fetchTimetable(arsId:routeId:dayType:), 디스크 캐시 (App Support/transit_data/bus_timetable/)
- [x] T028 [US4] `Navigation/Navigation/Navigation/Feature/Transit/BusStopTimetableDrawerViewController.swift` 생성 — 노선 선택 피커, 평일/토/일 탭, 시간 그리드

**Checkpoint**: 시간표 드로어 표시 + 캐시 동작 확인.

---

## Phase 7: User Story 5 - 지하철역 상세 + 실시간 도착 (Priority: P5)

**Goal**: 지하철 마커 탭 → 호선별 상/하행 실시간 도착 시트

**Independent Test**: 지하철 마커 탭 → 시트 열림 → 로그: `Arrivals fetched: N trains` 확인

### Implementation for User Story 5

- [x] T029 [US5] `Navigation/Navigation/Navigation/Service/SeoulOpenAPI/Subway/SubwayAPIClient.swift` 생성 — swopenAPI.seoul.go.kr 클라이언트, recptnDt 보정 유틸리티
- [x] T030 [US5] `Navigation/Navigation/Navigation/Feature/MapItemDetail/Content/SubwayStationContent.swift` 생성 — MapItemContent 구현, 호선별 섹션, 상/하행 각 2개 도착
- [x] T031 [US5] `Navigation/Navigation/Navigation/Feature/MapItemDetail/Content/SubwayStationContentView.swift` 생성 — 호선별 도착 정보 UI
- [x] T032 [US5] `AppCoordinator.swift` 수정 — showSubwayStationDetail(_:), onLineTapped, onWalkingRoute 연결

**Checkpoint**: 지하철 마커 탭 → 호선별 상/하행 도착 표시. 환승역 섹션 분리.

---

## Phase 8: User Story 6 - 지하철 노선 상세 (Priority: P6)

**Goal**: 호선 탭 → 지도 노선 폴리라인 + 역 목록 드로어

**Independent Test**: 호선 탭 → 지도에 호선 색상 폴리라인 표시 + 역 목록

### Implementation for User Story 6

- [x] T033 [US6] `Navigation/Navigation/Navigation/Feature/Transit/SubwayLineDrawerViewController.swift` 생성 — 호선명/방향 헤더, 역 목록, 역 탭 → 지도 이동
- [x] T034 [US6] `MapViewController` 수정 — showSubwayLinePolyline(stationCoords:color:isCircular:) 추가 (2호선 순환선 처리)
- [x] T035 [US6] `AppCoordinator.swift` 수정 — showSubwayLine(stationCode:lineName:), Phase 3와 동일한 드로어 스택 제한 적용

**Checkpoint**: 호선 탭 → 폴리라인 + 역 목록. 2호선 순환선 폐곡선 확인.

---

## Phase 9: User Story 7 - 지하철 시간표 (Priority: P7)

**Goal**: 시간표 버튼 탭 → 호선/방향/요일별 시간 그리드

**Independent Test**: 시간표 버튼 탭 → 로그: `Timetable fetched: N entries, saved to disk` (재조회 시 `Timetable cache hit (disk)`)

### Implementation for User Story 7

- [x] T036 [US7] `Navigation/Navigation/Navigation/Service/SeoulOpenAPI/Subway/SubwayTimetableAPI.swift` 생성 — OA-101 API, 디스크 캐시 (App Support/transit_data/subway_timetable/)
- [x] T037 [US7] `Navigation/Navigation/Navigation/Feature/Transit/SubwayStationTimetableDrawerViewController.swift` 생성 — 호선/방향/요일 선택, 시간 그리드

**Checkpoint**: 시간표 드로어 표시 + 캐시 동작 확인.

---

## Phase 10: User Story 8 - 설정 화면 데이터 갱신 (Priority: P8)

**Goal**: 설정에서 버스/지하철 데이터 수동 갱신 (하루 1회 제한)

**Independent Test**: 설정 화면 → 새로고침 버튼 탭 → 로그: `Manual refresh started` → 완료 후 날짜 갱신 확인

### Implementation for User Story 8

- [x] T038 [US8] `TransitDataService.swift` 수정 — canRefreshToday() last_updated.json 날짜 비교, clearTimetableCache()
- [x] T039 [US8] `Navigation/Navigation/Navigation/Feature/Settings/` 수정 — 지도 데이터 섹션 추가 (버스/지하철/시간표 마지막 업데이트 날짜, 새로고침 버튼, 하루 1회 제한)

**검증 로그**:
```
Logger.transit.info("Manual refresh started")
Logger.transit.info("Downloaded bus_stops: \(count) stops")
Logger.transit.warning("Refresh blocked: already updated today")
Logger.transit.error("Refresh failed: \(error)")
```

**Checkpoint**: 설정 화면에서 갱신 가능, 날짜 표시, 하루 1회 제한 동작.

---

## Phase 11: Polish & Cross-Cutting Concerns

- [x] T040 [P] 번들에 fallback JSON 3개 추가 — Xcode 프로젝트에 bus_stops_seoul.json, subway_stations_seoul.json, subway_lines_seoul.json 포함
- [x] T041 [P] 로거 카테고리 추가 — `Logger.transit`, `Logger.busAPI`, `Logger.subwayAPI` extension 추가
- [x] T042 도보 경로 연결 — BusStop/SubwayStation 상세에서 도보 길찾기 버튼 → 기존 RoutePreview 도보 모드 연결

---

## Dependencies & Execution Order

### Phase 의존성

- **Phase 1 (Setup)**: 즉시 시작 가능
- **Phase 2 (Foundational)**: Phase 1 완료 후 — **모든 User Story 블로킹**
- **Phase 3 (US1 마커)**: Phase 2 완료 후 시작 — MVP 완료 기준
- **Phase 4~10**: Phase 2 완료 후 순차 진행 (US1 → US2 → ...)
- **Phase 11 (Polish)**: 원하는 User Story 완료 후

### User Story 의존성

- **US1**: Phase 2 완료 후 독립 시작 가능
- **US2**: US1 완료 후 (마커 탭 이벤트 필요)
- **US3**: US2 완료 후 (버스 상세 시트에서 노선 탭)
- **US4**: US2 완료 후 (버스 상세에서 시간표 버튼)
- **US5**: US1 완료 후 독립 시작 가능 (US2와 병렬 가능)
- **US6**: US5 완료 후
- **US7**: US5 완료 후 (US6와 병렬 가능)
- **US8**: Phase 2 완료 후 독립 시작 가능

### 병렬 기회

- T010~T013 (Annotation 파일들): 동시 작업 가능
- T014~T015 (BusViewModel, SubwayViewModel): 동시 작업 가능
- US2~US4 (버스 계열)와 US5~US7 (지하철 계열): 병렬 진행 가능

---

## Implementation Strategy

### MVP (User Story 1만)

1. Phase 1: Setup 완료
2. Phase 2: TransitDataService 완료
3. Phase 3: US1 마커 표시 완료
4. **STOP & VALIDATE**: POI 팝업 → 버스/지하철 마커 동작 확인
5. 이후 US2~US8 순차 추가

### 단계별 배포

- US1 완료 → 마커 표시 (MVP)
- US2~US4 완료 → 버스 완전 기능
- US5~US7 완료 → 지하철 완전 기능
- US8 완료 → 데이터 갱신 기능

---

## Notes

- [P] 태스크는 다른 파일 작업으로 병렬 실행 가능
- 각 Phase 완료 시 로그 확인 후 커밋
- `pbxproj` 수동 파일 참조 추가 금지 (auto-sync 폴더 사용)
- Swift 6: delegate에 `nonisolated` 필요 시 `MainActor.assumeIsolated` 패턴 적용
