# 버스/지하철 구현 계획

> 작성일: 2026-05-31  
> 참고: [requirements.md](requirements.md), [api_research.md](api_research.md)

---

## 사전 준비 (개발 시작 전 — 직접 처리 필요)

개발 시작 전 아래 항목이 완료되어야 합니다.

### P1. API 키 발급

| 항목 | URL | 방법 | 상태 |
|------|-----|------|------|
| 버스 API 키 | https://www.data.go.kr/data/15000314/openapi.do | 공공데이터포털 활용신청 | ✅ 완료 |
| 지하철 시간표 키 | 서울 열린데이터광장 OA-101 | 기존 키 재사용 | ✅ 불필요 |

> ~~KRIC 키 불필요~~ — 지하철 시간표는 서울 열린데이터광장 OA-101 (`openapi.seoul.go.kr:8088`) 사용. 기존 `SEOUL_OPEN_API_KEY` 재사용.

`Secrets.xcconfig` 현재 상태:
```
KAKAO_REST_API_KEY = ...
KAKAO_MOBILITY_APP_KEY = ...
SEOUL_OPEN_API_KEY = ...     ← 지하철 실시간 도착 + 시간표 재사용
BUS_API_KEY = ...            ← 버스 정류소/도착/노선/시간표
```

---

### P2. Firebase 프로젝트 설정

1. Firebase 콘솔(https://console.firebase.google.com)에서 프로젝트 생성 또는 기존 프로젝트 사용
2. iOS 앱 등록 → `GoogleService-Info.plist` 다운로드 → 프로젝트에 추가 ✅ 완료
3. **Remote Config** 활성화 ✅ 완료
4. ~~Storage 활성화~~ — Spark 플랜에서 사용 불가. **GitHub Gist 방식으로 대체**

Firebase SDK (SPM): FirebaseAnalytics, FirebaseCrashlytics, FirebaseRemoteConfig ✅ 완료  
`AppDelegate`에서 `FirebaseApp.configure()` 호출 ✅ 완료

---

### P3. 정적 데이터 준비 및 배포

데이터 갱신 시 앱 업데이트 없이 배포하기 위해 **GitHub Gist (public)** 을 사용합니다.  
변환 스크립트 및 상세 가이드: [Scripts/TransitData/README.md](../../../Navigation/Scripts/TransitData/README.md)

#### 데이터 변환 ✅ 완료

`Scripts/TransitData/convert.py` 실행 → `output/` 에 JSON 4개 생성:

| 파일 | 내용 | 버전 |
|------|------|------|
| `version.json` | 각 파일 버전 정보 | — |
| `bus_stops_seoul.json` | 11,250개 버스 정류장 | 20260506 |
| `subway_stations_seoul.json` | 276개 지하철역 (1~8호선) | 20250814 |
| `subway_lines_seoul.json` | 8개 호선 색상 + 역 순서 | 20260603 |

#### GitHub Gist 업로드 (직접 처리 필요)

1. [gist.github.com](https://gist.github.com) 접속
2. `output/` 폴더의 파일 4개 업로드 (**Create public gist**)
3. 각 파일의 **Raw** URL 확인 (commit hash 없는 형식 사용)
4. URL을 [Scripts/TransitData/README.md](../../../Navigation/Scripts/TransitData/README.md) Gist URL 표에 기록
5. 앱 코드의 Gist URL 상수에 등록 (Phase 1-2에서 처리)

---

## Phase 1. 정적 데이터 로드 + 마커 표시

**목표**: 정류장/역 데이터 로드, 지도 마커 표시  
**검증**: 지도에 버스 정류장 + 지하철역 마커가 정상 표시되는지 확인

### 1-1. Firebase 초기화 확인 ✅ 완료

- Firebase SPM 패키지: FirebaseAnalytics, FirebaseCrashlytics, FirebaseRemoteConfig ✅
- `GoogleService-Info.plist` 추가 ✅
- `AppDelegate`에서 `FirebaseApp.configure()` 호출 ✅

### 1-2. TransitDataService 구현

`Service/Transit/TransitDataService.swift`

**동작 흐름:**
1. Gist의 `version.json` fetch → 로컬 캐시 버전과 비교
2. 버전이 다른 파일만 Gist에서 다운로드 → `Documents/TransitData/` 에 저장
3. 로컬 파일 있으면 로컬 사용, 없으면 앱 번들 fallback
4. `CurrentValueSubject<TransitDataState, Never>` 로 상태 노출

```swift
enum TransitDataState {
    case loading
    case loaded(busStops: [BusStop], subwayStations: [SubwayStation], lines: SubwayLines)
    case failed(Error)
}
```

Gist Raw URL 상수 (`Service/Transit/TransitGistURLs.swift`):
```swift
enum TransitGistURLs {
    static let version       = "https://gist.githubusercontent.com/.../raw/version.json"
    static let busStops      = "https://gist.githubusercontent.com/.../raw/bus_stops_seoul.json"
    static let subwayStations = "https://gist.githubusercontent.com/.../raw/subway_stations_seoul.json"
    static let subwayLines   = "https://gist.githubusercontent.com/.../raw/subway_lines_seoul.json"
}
```

> ⚠️ URL은 Gist 업로드 후 채워 넣음 (P3 완료 후)

**로그 확인 포인트**
```swift
Logger.transit.info("Firebase configured")
Logger.transit.info("version.json fetched: busStops=\(busVer), stations=\(stationVer)")
Logger.transit.info("bus_stops downloaded: \(count) stops")
Logger.transit.info("subway_stations downloaded: \(count) stations")
Logger.transit.info("Using cached bus_stops (version up to date)")
Logger.transit.warning("Gist fetch failed, using bundle fallback")
```

### 1-3. 모델 정의

- `BusStop`: stId, arsId, name, coordinate
- `SubwayStation`: stationCode, name, nameEn, coordinate, lines
- `SubwayLines`: 호선별 색상 + 역 순서

### 1-4. POI 레이어 팝업 UI

`MapControlButtonsView` 수정:
- 기존 자전거 토글 + 새로고침 버튼 제거
- POI 레이어 버튼 1개 추가
- `POILayerPopupView`: 따릉이/버스/지하철 토글 목록

### 1-5. 버스/지하철 Annotation + AnnotationView

- `BusStopAnnotation`: coordinate, busStop 참조
- `BusStopAnnotationView`: 버스 색상 마커
- `SubwayStationAnnotation`: coordinate, station 참조, lines(호선 색상)
- `SubwayStationAnnotationView`: 호선 색상 마커 (환승역은 복합 색상)

### 1-6. MapViewController 확장

```swift
func setBusStops(_ stops: [BusStop])
func setSubwayStations(_ stations: [SubwayStation])
func clearBusStops()
func clearSubwayStations()
```

줌 임계값: 버스 `latΔ ≤ 0.03`, 지하철 `latΔ ≤ 0.15`

### 1-7. BusViewModel / SubwayViewModel

- `isLayerOn: Bool`
- `toggleLayer()`
- TransitDataService 구독 → 데이터 로드 시 마커 업데이트

**Phase 1 검증 체크리스트**
- [ ] Firebase 초기화 로그 출력
- [ ] version.json fetch 성공 로그 출력
- [ ] 버스 정류장 JSON 로드 → 정류소 수 로그 출력 (`"bus_stops downloaded: 11250 stops"`)
- [ ] 지하철역 JSON 로드 → 역 수 로그 출력 (`"subway_stations downloaded: 276 stations"`)
- [ ] 재실행 시 캐시 사용 로그 출력 (`"Using cached bus_stops"`)
- [ ] POI 팝업에서 버스 ON → 지도에 마커 표시
- [ ] POI 팝업에서 지하철 ON → 지도에 마커 표시
- [ ] 줌 아웃 시 버스 마커 숨김 / 줌 인 시 다시 표시
- [ ] Fallback 동작: 네트워크 차단 후 실행 → 번들 JSON으로 마커 표시

---

## Phase 2. 버스 정류장 상세 + 실시간 도착

**목표**: 버스 마커 탭 → 상세 시트 → 실시간 도착 정보  
**전제**: 버스 API 키 발급 완료

### 2-1. BusAPIClient 구현

`Service/SeoulOpenAPI/Bus/BusAPIClient.swift`

- `ws.bus.go.kr` HTTP 클라이언트
- API 키: `Info.plist`에서 로드 (`BUS_API_KEY`)
- 기존 `SeoulAPIClient` 패턴 동일 적용

**로그 확인 포인트**
```swift
Logger.busAPI.info("Fetching arrivals for arsId=\(arsId)")
Logger.busAPI.info("Arrivals fetched: \(routes.count) routes")
Logger.busAPI.error("Bus API error: \(error)")
```

### 2-2. 버스 도착 모델

```swift
struct BusArrival {
    let routeId: String
    let routeName: String      // 노선 번호 (예: "140")
    let direction: String      // 방향 (예: "방화역")
    let firstArrivalSeconds: Int?
    let secondArrivalSeconds: Int?
    let firstArrivalMessage: String   // "3분 후", "곧 도착", "운행 종료"
    let secondArrivalMessage: String
    let routeType: BusRouteType
    let isLastBus: Bool
}
```

### 2-3. BusStopContent 구현

`Feature/MapItemDetail/Content/BusStopContent.swift`

- `MapItemContent` 프로토콜 구현
- `BusStopContentView`: 노선별 도착 정보 목록 + 새로고침 버튼
- 노선 행 탭 → `onRouteTapped(routeId:)` 콜백
- 풋터: [시간표], [도보 길찾기]

### 2-4. AppCoordinator 연동

```swift
func showBusStopDetail(_ stop: BusStop)
```

- BusStopContent 생성 + MapItemDetailViewController push
- `onRouteTapped` → `showBusRoute(routeId:from:stop:)`
- `onTimetableTapped` → `showBusStopTimetable(stop:)`
- `onWalkingRoute` → `showWalkingRouteToBusStop(stop:)`

**Phase 2 검증 체크리스트**
- [ ] 버스 마커 탭 → 상세 시트 열림
- [ ] 시트 진입 시 API 호출 로그 출력
- [ ] 경유 노선 목록 + 도착 정보 표시
- [ ] 도착 정보 없는 노선 "운행 종료" 표시
- [ ] 새로고침 버튼 → API 재호출 로그 + 데이터 갱신
- [ ] 도보 길찾기 → RoutePreview 도보 모드 진입

---

## Phase 3. 버스 노선 상세

**목표**: 노선 탭 → 지도 폴리라인 + 경유 정류소 드로어  

### 3-1. 버스 노선 API

```swift
// BusAPIClient 확장
func fetchRouteStops(routeId: String) async throws -> [BusRouteStop]
func fetchRoutePolyline(routeId: String) async throws -> [CLLocationCoordinate2D]
```

인메모리 캐시: `[String: [BusRouteStop]]`, `[String: [CLLocationCoordinate2D]]`

**로그 확인 포인트**
```swift
Logger.busAPI.info("Route stops cache hit: routeId=\(routeId)")
Logger.busAPI.info("Route stops fetched: \(stops.count) stops for routeId=\(routeId)")
Logger.busAPI.info("Polyline fetched: \(coords.count) points for routeId=\(routeId)")
```

### 3-2. BusRouteDrawerViewController

- 헤더: 노선명 + 기종점
- 정류소 목록 (현재 정류소 강조)
- 정류소 탭 → 지도 카메라 이동 (드로어 유지)

### 3-3. MapViewController 폴리라인 처리

```swift
func showBusRoutePolyline(_ coords: [CLLocationCoordinate2D], color: UIColor)
func clearTransitPolyline()
```

### 3-4. 드로어 스택 규칙 구현

AppCoordinator에 스택 제어 로직:
- [4] 정류장 상세: 항상 1개 유지
- [5a] 노선 드로어: 항상 1개 유지
- 지도 마커 탭 시 [5a] 열려있으면 팝 후 [4] 교체

**Phase 3 검증 체크리스트**
- [ ] 노선 탭 → 드로어 push + 지도 폴리라인 표시
- [ ] 폴리라인 색상 노선 유형별 확인
- [ ] 정류소 목록에서 탭 → 지도 카메라 이동, 드로어 유지
- [ ] 지도에서 다른 정류소 마커 탭 → 노선 드로어 닫힘 + 정류장 상세 교체 + 폴리라인 제거
- [ ] 같은 노선 재진입 → 캐시 hit 로그 출력 (API 재호출 없음)
- [ ] 다른 노선 탭 → 드로어 컨텐츠 교체 + 새 폴리라인
- [ ] 뒤로가기 → 정류장 상세 복귀 + 폴리라인 제거
- [ ] 스택 최대 2단계 유지 확인

---

## Phase 4. 버스 시간표

**목표**: 시간표 버튼 → 노선/요일별 시간표  

### 4-1. 버스 시간표 API

```swift
func fetchTimetable(arsId: String, routeId: String, dayType: BusDayType) async throws -> [String]
// dayType: .weekday / .saturday / .sunday
```

캐시 전략: 디스크 영구 저장 (`App Support/transit_data/bus_timetable/{arsId}_{routeId}_{dayType}.json`)
- 최초 조회 시 API 호출 → 디스크 저장
- 이후 동일 조합은 디스크 캐시 사용 (네트워크 없음)
- 설정 화면 수동 갱신 시 캐시 삭제 → 재조회

### 4-2. BusStopTimetableDrawerViewController

- 노선 선택 피커 (해당 정류소 경유 노선 목록)
- 평일/토/일 탭
- 시간 그리드 표시

**Phase 4 검증 체크리스트**
- [ ] 시간표 버튼 탭 → 시간표 드로어 push
- [ ] 노선/요일 변경 → API 호출 로그 + 데이터 갱신
- [ ] 같은 노선+요일 재선택 → 캐시 hit 로그 (API 재호출 없음)
- [ ] 뒤로가기 → 정류장 상세 복귀

---

## Phase 5. 지하철역 상세 + 실시간 도착

**목표**: 지하철 마커 탭 → 상세 시트 → 실시간 도착 정보  
**전제**: 기존 서울 열린데이터광장 키 재사용

### 5-1. SubwayAPIClient 구현

`Service/SeoulOpenAPI/Subway/SubwayAPIClient.swift`

- `swopenAPI.seoul.go.kr` 클라이언트
- `recptnDt` 시간 보정 유틸리티

**로그 확인 포인트**
```swift
Logger.subwayAPI.info("Fetching arrivals for station=\(stationName)")
Logger.subwayAPI.info("Arrivals fetched: \(arrivals.count) trains")
Logger.subwayAPI.debug("recptnDt correction: \(correction)s applied")
```

### 5-2. SubwayArrival 모델

```swift
struct SubwayArrival {
    let lineName: String           // "2호선"
    let direction: String          // "상행" / "하행" / "외선" / "내선"
    let destination: String        // "성수행"
    let arrivalSeconds: Int        // recptnDt 보정 적용
    let arrivalMessage: String     // "2분 후", "곧 도착", "진입"
    let arrivalCode: ArrivalCode   // .approaching / .arrived / .departed ...
    let isExpress: Bool
}
```

### 5-3. SubwayStationContent 구현

- 호선별 섹션 분리 표시
- 상/하행 실시간 도착 (각 2개)
- 새로고침 버튼
- 풋터: [시간표], [도보 길찾기]

**Phase 5 검증 체크리스트**
- [ ] 지하철 마커 탭 → 상세 시트 열림
- [ ] 실시간 도착 API 호출 로그
- [ ] 호선별 상/하행 도착 표시
- [ ] 환승역 → 호선별 섹션 분리 확인
- [ ] recptnDt 보정 적용 로그 (`"correction: 12s"`)
- [ ] 새로고침 → API 재호출
- [ ] 도보 길찾기 → RoutePreview 도보 모드

---

## Phase 6. 지하철 노선 상세

**목표**: 호선 탭 → 지도 노선 오버레이 + 역 목록  

### 6-1. SubwayLineDrawerViewController

- 호선명 + 방향 헤더
- 역 목록 (현재 역 강조, 호선 색상)
- 역 탭 → 지도 카메라 이동 (드로어 유지)

### 6-2. MapViewController 지하철 노선 폴리라인

```swift
func showSubwayLinePolyline(stationCoords: [CLLocationCoordinate2D], color: UIColor, isCircular: Bool)
```

순환선(2호선): 마지막 좌표와 첫 좌표 연결

**Phase 6 검증 체크리스트**
- [ ] 호선 탭 → 드로어 push + 지도 노선 표시
- [ ] 호선 색상 정확히 적용 확인 (1~9호선 각각)
- [ ] 2호선 순환선 폐곡선 확인
- [ ] 역 탭 → 지도 카메라 이동, 드로어 유지
- [ ] 지도에서 다른 역 마커 탭 → 노선 드로어 닫힘 + 역 상세 교체
- [ ] Phase 3과 동일한 스택 2단계 유지 확인

---

## Phase 7. 지하철 시간표

**목표**: 시간표 버튼 → 호선/방향/요일별 시간표  
**전제**: 기존 서울 열린데이터광장 키 재사용 (추가 키 불필요)

### 7-1. SubwayTimetableAPI 구현

`Service/SeoulOpenAPI/Subway/SubwayTimetableAPI.swift`

- API: 서울 열린데이터광장 OA-101 (`서울교통공사_역코드로 지하철 열차 시간표 검색`)
- 호스트: `openapi.seoul.go.kr:8088`
- 기존 `SeoulAPIClient` 재사용

```swift
func fetchTimetable(
    stationCode: String,    // 전철역코드
    direction: SubwayDirection,  // 1=상행/내선, 2=하행/외선
    dayType: SubwayDayType       // 1=평일, 2=토요일, 3=일요일/공휴일
) async throws -> [SubwayTimetableEntry]
```

캐시 전략: 디스크 영구 저장 (`App Support/transit_data/subway_timetable/{stationCode}_{direction}_{dayType}.json`)
- 최초 조회 시 API 호출 → 디스크 저장
- 이후 동일 조합은 디스크 캐시 사용 (네트워크 없음)
- 설정 화면 수동 갱신 시 캐시 삭제 → 재조회

**로그 확인 포인트**
```swift
Logger.subwayAPI.info("Fetching timetable OA-101: station=\(stationCode)")
Logger.subwayAPI.info("Timetable fetched: \(times.count) entries, saved to disk")
Logger.subwayAPI.info("Timetable cache hit (disk): \(cacheKey)")
```

### 7-2. SubwayStationTimetableDrawerViewController

- 호선 / 방향 / 요일 선택
- 시간 그리드 표시

**Phase 7 검증 체크리스트**
- [ ] 시간표 버튼 탭 → 시간표 드로어 push
- [ ] 호선/방향/요일 변경 → API 호출 로그 + 갱신
- [ ] 캐시 hit → API 재호출 없음 로그
- [ ] 뒤로가기 → 역 상세 복귀

---

## Phase 8. 설정 + 데이터 갱신 UI

**목표**: 설정 화면에 데이터 업데이트 기능 추가  

### 8-1. TransitDataManager 갱신 로직

```swift
// 수동 갱신 — 하루 1회 제한
func refreshAll() async throws
func canRefreshToday() -> Bool   // last_updated.json 날짜 비교

// 시간표 캐시 초기화
func clearTimetableCache()

// 마지막 업데이트 날짜
func lastUpdatedDate() -> Date?
```

**로그 확인 포인트**
```swift
Logger.transit.info("Manual refresh started")
Logger.transit.info("Downloaded bus_stops: \(count) stops")
Logger.transit.info("Downloaded subway_stations: \(count) stations")
Logger.transit.info("Timetable cache cleared")
Logger.transit.warning("Refresh blocked: already updated today")
Logger.transit.error("Refresh failed: \(error)")
```

### 8-2. 설정 화면 추가 항목

```
지도 데이터
  버스 정류장    마지막 업데이트: 2026.05.31
  지하철역       마지막 업데이트: 2026.05.31
  시간표         마지막 업데이트: 2026.05.31

  [지금 업데이트]   ← 오늘 이미 업데이트 시 비활성화 + "오늘 업데이트됨" 표시
```

- 업데이트 중: 프로그레스 인디케이터 표시
- 완료: 날짜 즉시 갱신
- 실패: 에러 메시지 표시, 기존 데이터 유지

**Phase 8 검증 체크리스트**
- [ ] 설정 화면에 항목별 마지막 업데이트 날짜 표시
- [ ] 업데이트 버튼 탭 → 다운로드 로그 출력 → 완료 후 날짜 갱신
- [ ] 오늘 이미 업데이트 → 버튼 비활성화 로그 출력
- [ ] 업데이트 완료 후 시간표 캐시 삭제 로그 출력
- [ ] 네트워크 없는 상태 → 실패 에러 메시지, 기존 데이터 유지 확인
- [ ] Fallback 동작: 로컬 파일 삭제 후 실행 → 번들 JSON으로 마커 표시

---

## 전체 일정 요약

| Phase | 내용 | 전제 조건 |
|-------|------|----------|
| 사전 준비 | API 키 발급, Firebase 설정, 데이터 준비 | 직접 처리 필요 |
| Phase 1 | Firebase + 마커 표시 | 사전 준비 완료 |
| Phase 2 | 버스 상세 + 실시간 도착 | 버스 API 키 |
| Phase 3 | 버스 노선 상세 | Phase 2 |
| Phase 4 | 버스 시간표 | Phase 2 |
| Phase 5 | 지하철 상세 + 실시간 도착 | Phase 1 |
| Phase 6 | 지하철 노선 상세 | Phase 5 |
| Phase 7 | 지하철 시간표 | Phase 5 (기존 키 재사용) |
| Phase 8 | 설정 + 데이터 갱신 | Phase 1 |

> Phase 2~4 (버스)와 Phase 5~7 (지하철)는 병렬 진행 가능
