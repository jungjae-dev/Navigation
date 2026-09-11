# 버스/지하철 기능 요구사항

> 작성일: 2026-05-31  
> 단계: 1단계 — 서울 한정  
> 참고: [api_research.md](api_research.md)

---

## 목차

1. [범위 및 전제](#1-범위-및-전제)
2. [API 키 요구사항](#2-api-키-요구사항)
3. [화면 시나리오](#3-화면-시나리오)
4. [기능 요구사항](#4-기능-요구사항)
5. [기존 구조 변경 포인트](#5-기존-구조-변경-포인트)
6. [데이터 요구사항](#6-데이터-요구사항)
7. [비기능 요구사항](#7-비기능-요구사항)
8. [미결 사항](#8-미결-사항)

---

## 1. 범위 및 전제

- **지역**: 서울시 한정 (추후 전국 확장 예정)
- **대상**: 버스 정류장, 지하철역 (서울 1~9호선, 서울교통공사 운영 구간)
- **기존 구조 유지**: MapItemContent 프로토콜, DrawerManager 스택, AppCoordinator 패턴

---

## 2. API 키 요구사항

| 키 | 용도 | 발급처 | 상태 |
|----|------|--------|------|
| 서울 열린데이터광장 | 지하철 실시간 도착, 역명 검색 | [data.seoul.go.kr](https://data.seoul.go.kr) | ✅ 기존 보유 |
| 버스 API 키 | 버스 정류소 정보, 실시간 도착, 노선, 시간표 | [api.bus.go.kr](http://api.bus.go.kr) | ❌ 신규 발급 필요 |
| KRIC 레일포털 키 | 지하철 시간표 | [data.kric.go.kr](https://data.kric.go.kr) | ❌ 신규 발급 필요 |

---

## 3. 화면 시나리오

### 3-1. POI 레이어 선택

**트리거**: 지도 우측 컨트롤 버튼 중 "레이어" 버튼 탭

```
[레이어 버튼 탭]
    ↓
레이어 선택 팝업 표시 (버튼 기준 앵커)
    ┌──────────────────┐
    │  지도에 표시할 항목  │
    │  ☑ 따릉이         │
    │  ☐ 버스 정류장     │
    │  ☐ 지하철역       │
    └──────────────────┘
    각 항목 토글 → 해당 레이어 즉시 표시/숨김
```

- 기존 자전거 토글 버튼 + 새로고침 버튼을 이 팝업으로 통합
- 추후 서울시 공공데이터 항목 추가 시 목록에 추가만 하면 됨
- 각 레이어 상태는 앱 재시작 시 초기화 (저장 불필요)

---

### 3-2. 버스 정류장 마커 → 상세 시트

**트리거**: 버스 레이어 ON 상태에서 정류장 마커 탭

```
[정류장 마커 탭]
    ↓
MapItemDetailViewController (기존 시트 재사용)
    ┌────────────────────────────────┐
    │ 🚌  강남역사거리 (23456)      ✕ │  ← 헤더 (정류소명 + ARS ID)
    ├────────────────────────────────┤
    │  140   방화역    [3분 후] [8분] │  ← 노선번호 + 방향 + 도착 정보
    │  341   신촌역    [곧 도착]      │
    │  3412  수서역    [운행 종료]    │
    │  ...                           │
    │                      🔄        │  ← 새로고침 버튼 (우하단)
    ├────────────────────────────────┤
    │  [시간표]       [도보 길찾기]   │  ← 풋터 버튼 2개
    └────────────────────────────────┘

각 노선 행 탭 → 3-3 노선 상세
[시간표] 탭    → 3-4 버스 시간표
[도보 길찾기]  → RoutePreviewDrawerViewController (도보 모드 고정)
```

- 시트 진입 시 경유 노선 목록 + 도착 정보 1회 자동 조회
- 새로고침 버튼: 도착 정보 재조회 (노선 목록 재조회 불필요)
- 도착 정보 없는 노선: "운행 종료" 또는 "정보 없음" 표시

---

### 3-3. 버스 노선 상세 (지도 + 드로어)

**트리거**: 정류장 상세 시트에서 노선 행 탭

```
[노선 행 탭 (예: 140번)]
    ↓
drawerManager.pushDrawer(BusRouteDrawerViewController)
지도: 140번 노선 폴리라인 오버레이 표시

    ┌────────────────────────────────┐
    │ ←  140번  강남역 ↔ 방화역     │  ← 헤더 (뒤로가기 + 노선명 + 기종점)
    ├────────────────────────────────┤
    │  • 방화역                       │
    │  • 개화역                       │
    │  ...                           │
    │  • 강남역사거리  ◀ 현재 위치    │  ← 현재 정류소 강조
    │  • 역삼역                       │
    │  • 선릉역                       │
    │  ...                           │
    └────────────────────────────────┘

뒤로가기(←) → 정류장 상세 시트로 복귀, 노선 폴리라인 제거
정류소 행 탭 → 지도 카메라 해당 정류소로 이동 (드로어 유지, 상세 전환 없음)
지도에서 정류소 마커 탭 → [5a] 팝 + 폴리라인 제거 + [4] 해당 정류장 상세로 전환
```

- 폴리라인: `ws.bus.go.kr/getRoutePath` WGS84 좌표 배열로 MKPolyline 생성
- 정류소 목록: `ws.bus.go.kr/getStaionByRoute` (순서 포함)
- 지도 카메라: 노선 전체가 보이도록 자동 조정
- 드로어 닫힘 시 폴리라인 제거

---

### 3-4. 버스 정류장 시간표

**트리거**: 정류장 상세 시트 하단 [시간표] 버튼 탭

```
drawerManager.pushDrawer(BusStopTimetableDrawerViewController)
    ┌────────────────────────────────┐
    │ ←  강남역사거리 시간표          │
    ├────────────────────────────────┤
    │  [140번 ▾]        [평일 ▾]    │  ← 노선 선택 + 평일/토/일 선택
    ├────────────────────────────────┤
    │  05:30  05:58  06:15  06:32   │
    │  06:50  07:08  07:20  07:35   │
    │  ...                           │
    │  23:10  23:40                  │
    └────────────────────────────────┘

뒤로가기(←) → 정류장 상세 시트로 복귀
```

- 노선 선택: 해당 정류소 경유 노선 목록 (상세 시트에서 전달)
- 평일/토요일/일요일·공휴일 탭 전환
- API: `ws.bus.go.kr/getBustimeByStation`

---

### 3-5. 지하철역 마커 → 상세 시트

**트리거**: 지하철 레이어 ON 상태에서 역 마커 탭

```
[역 마커 탭]
    ↓
MapItemDetailViewController (기존 시트 재사용)
    ┌────────────────────────────────┐
    │ 🚇  강남역                   ✕ │  ← 헤더
    ├────────────────────────────────┤
    │  ●  2호선                      │
    │  ↑ 성수 방향   [2분] [10분]    │
    │  ↓ 사당 방향   [4분] [12분]    │
    │                                │
    │  ●  신분당선                   │
    │  ↑ 광교 방향   [3분] [9분]     │
    │  ↓ 강남 방향   [1분] [7분]     │
    │                      🔄        │  ← 새로고침 버튼
    ├────────────────────────────────┤
    │  [시간표]       [도보 길찾기]   │
    └────────────────────────────────┘

각 호선 행 탭 → 3-6 지하철 노선 상세
[시간표] 탭    → 3-7 지하철 시간표
[도보 길찾기]  → RoutePreviewDrawerViewController (도보 모드 고정)
```

- 환승역: 호선별 섹션 분리 표시
- `barvlDt - (현재시각 - recptnDt)` 보정 후 표시
- 도착 코드(`arvlCd`) 기반 메시지: 0=진입, 1=도착, 2=출발, 3=전역출발...

---

### 3-6. 지하철 노선 상세 (지도 + 드로어)

**트리거**: 역 상세 시트에서 호선 탭

```
[2호선 탭]
    ↓
drawerManager.pushDrawer(SubwayLineDrawerViewController)
지도: 2호선 경로 표시 (역 좌표 직선 연결 근사, 호선 색상)

    ┌────────────────────────────────┐
    │ ←  ● 2호선  외선순환           │
    ├────────────────────────────────┤
    │  • 시청                        │
    │  • 을지로입구                   │
    │  ...                           │
    │  • 강남  ◀ 현재 역             │
    │  • 역삼                        │
    │  • 선릉                        │
    │  ...                           │
    └────────────────────────────────┘

뒤로가기(←) → 역 상세 시트로 복귀, 노선 오버레이 제거
역 행 탭 → 지도 카메라 해당 역으로 이동 (드로어 유지, 상세 전환 없음)
지도에서 역 마커 탭 → [5a] 팝 + 노선 오버레이 제거 + [4] 해당 역 상세로 전환
```

- 폴리라인: 번들 내장 역 좌표를 호선 순서대로 MKPolyline 연결
- 호선 색상: 공식 색상 코드 적용 (1호선 파랑, 2호선 초록 등)
- 순환선(2호선): 마지막 역과 첫 역 연결하여 폐곡선

---

### 3-7. 지하철 시간표

**트리거**: 역 상세 시트 하단 [시간표] 버튼 탭

```
drawerManager.pushDrawer(SubwayStationTimetableDrawerViewController)
    ┌────────────────────────────────┐
    │ ←  강남역 시간표               │
    ├────────────────────────────────┤
    │  [2호선 ▾]  [상행 ▾]  [평일 ▾]│  ← 호선 / 방향 / 요일 선택
    ├────────────────────────────────┤
    │  05:32  05:48  06:05  06:22   │
    │  06:40  06:55  07:10  07:22   │
    │  ...                           │
    │  23:55  00:12                  │
    └────────────────────────────────┘

뒤로가기(←) → 역 상세 시트로 복귀
```

- API: KRIC `openapi.kric.go.kr/openapi/trainUseInfo/subwayTimetable`
- 호선 선택: 해당 역 호선 목록 (상세 시트에서 전달)
- 방향: 상행/하행 (호선별 종착역명으로 레이블)
- 요일: 평일/토요일/일요일·공휴일

---

## 3-8. 드로어 스택 규칙

스택은 **최대 2단계**를 유지한다. 정류장/역 상세([4])와 노선 상세([5a])는 각각 스택에 1개만 존재한다.

```
최대 스택 구조:
  [4] 정류장/역 상세  (항상 1개)
  [5a] 노선 상세      (열려있을 때만, 1개)
```

**동작 규칙**

| 액션 | 동작 |
|------|------|
| 마커 탭 | [5a] 열려있으면 먼저 팝 → [4] 교체 또는 push |
| 노선/호선 탭 | [5a] 없으면 push, 있으면 컨텐츠 교체 |
| [5a] 목록에서 정류소/역 탭 | 지도 카메라 이동만 (드로어 유지) |
| [5a] 열린 상태에서 지도 마커 탭 | [5a] 팝 + 오버레이 제거 → [4] 해당 정류장/역 상세로 전환 |
| [5a] 뒤로가기 | [5a] 팝 + 오버레이 제거 → [4] 유지 |
| [4] 닫기(✕) | 스택 초기화, 오버레이 제거, 홈 드로어 복귀 |
| 도보 길찾기 | 스택 replace → [6] 경로요약 |

**흐름 예시**

```
강남역사거리 탭   →  스택: [4 강남역사거리]
140번 탭         →  스택: [4 강남역사거리] → [5a 140번]
역삼역 탭        →  스택: [4 역삼역]
140번 탭         →  스택: [4 역삼역] → [5a 140번]
341번 탭         →  스택: [4 역삼역] → [5a 341번]   ← 5a 컨텐츠 교체
뒤로가기         →  스택: [4 역삼역]
```

---

## 4. 기능 요구사항

### 4-1. POI 레이어 관리

- [ ] 레이어 선택 팝업 UI (MapControlButtonsView 교체)
- [ ] 따릉이/버스/지하철 각각 독립 토글 상태
- [ ] 레이어 ON 시 번들 데이터 로드 → 마커 표시
- [ ] 레이어 OFF 시 마커 즉시 제거
- [ ] 줌 임계값 이하에서 마커 숨김 (버스: 따릉이보다 좁은 임계값)

### 4-2. 버스 정류장

- [ ] 번들 JSON에서 정류장 로드 → 지도 마커 표시
- [ ] 마커 탭 → BusStopContent 시트 표시
- [ ] 경유 노선 + 실시간 도착 정보 조회 (시트 진입 시 1회)
- [ ] 새로고침 버튼으로 도착 정보 재조회
- [ ] 노선 탭 → 노선 상세 드로어 + 지도 폴리라인
- [ ] 시간표 버튼 → 시간표 드로어
- [ ] 도보 길찾기 → RoutePreview (도보 모드)

### 4-3. 버스 노선

- [ ] 경유 정류소 목록 조회 (`getStaionByRoute`)
- [ ] 노선 폴리라인 조회 (`getRoutePath`) → MKPolyline 오버레이
- [ ] 현재 정류소 강조 표시
- [ ] 다른 정류소 탭 → 해당 정류장 상세로 교체
- [ ] 드로어 닫힘 시 폴리라인 제거

### 4-4. 버스 시간표

- [ ] 노선 선택 세그먼트/피커
- [ ] 평일/토/일 탭 전환
- [ ] `getBustimeByStation` 호출 → 시간 그리드 표시

### 4-5. 지하철역

- [ ] 번들 JSON에서 역 좌표 로드 → 마커 표시 (호선 색상)
- [ ] 환승역: 마커 1개, 시트에서 호선별 섹션 분리
- [ ] `realtimeStationArrival` 호출 (시트 진입 시 1회)
- [ ] `recptnDt` 시간 보정 적용
- [ ] 새로고침 버튼으로 도착 정보 재조회
- [ ] 호선 탭 → 노선 상세 드로어 + 지도 폴리라인
- [ ] 시간표 버튼 → 시간표 드로어
- [ ] 도보 길찾기 → RoutePreview (도보 모드)

### 4-6. 지하철 노선

- [ ] 호선별 역 순서 목록 (번들 데이터 기반)
- [ ] 역 좌표 직선 연결 → MKPolyline 오버레이 (호선 색상)
- [ ] 순환선(2호선): 폐곡선 처리
- [ ] 현재 역 강조 표시
- [ ] 다른 역 탭 → 해당 역 상세로 교체
- [ ] 드로어 닫힘 시 폴리라인 제거

### 4-7. 지하철 시간표

- [ ] 호선 / 방향 / 요일 선택
- [ ] 서울 열린데이터광장 OA-101 호출 → 시간 그리드 표시

---

## 5. 기존 구조 변경 포인트

### Feature 레이어

| 파일/폴더 | 변경 내용 |
|----------|----------|
| `Feature/Home/MapControlButtonsView` | 자전거 토글+새로고침 버튼 → POI 레이어 버튼 1개로 교체 |
| `Feature/Home/HomeViewController` | POI 레이어 팝업 연동, 버스/지하철 ViewModel 바인딩 추가 |
| `Feature/MapItemDetail/Content/` | `BusStopContent`, `SubwayStationContent` 추가 |
| `Feature/Bus/` | `BusStopAnnotation`, `BusStopAnnotationView`, `BusViewModel` 추가 |
| `Feature/Bus/Route/` | `BusRouteDrawerViewController` 추가 |
| `Feature/Bus/Timetable/` | `BusStopTimetableDrawerViewController` 추가 |
| `Feature/Subway/` | `SubwayAnnotation`, `SubwayAnnotationView`, `SubwayViewModel` 추가 |
| `Feature/Subway/Line/` | `SubwayLineDrawerViewController` 추가 |
| `Feature/Subway/Timetable/` | `SubwayStationTimetableDrawerViewController` 추가 |

### Service 레이어

| 파일/폴더 | 변경 내용 |
|----------|----------|
| `Service/SeoulOpenAPI/Bus/` | `BusStopAPI`, `BusStopCache`, `BusStop`, `BusRoute` 모델 추가 |
| `Service/SeoulOpenAPI/Subway/` | `SubwayAPI`, `SubwayStationCache`, `SubwayStation` 모델 추가 |
| `Service/SeoulOpenAPI/Subway/` | `SubwayTimetableAPI` 추가 (OA-101, 기존 SeoulAPIClient 재사용) |

### Map 레이어

| 파일 | 변경 내용 |
|------|----------|
| `Map/MapViewController` | `setBusStops()`, `setSubwayStations()`, `showBusRoute()`, `showSubwayLine()`, `clearTransitOverlays()` 추가 |
| `Map/Annotation/` | `BusStopAnnotation`, `SubwayStationAnnotation` 추가 |
| `Map/Overlay/` | 버스 노선 / 지하철 노선 폴리라인 렌더러 추가 |

### Coordinator

| 파일 | 변경 내용 |
|------|----------|
| `Coordinator/AppCoordinator` | `showBusStopDetail()`, `showSubwayStationDetail()`, `showBusRoute()`, `showSubwayLine()`, `showBusStopTimetable()`, `showSubwayStationTimetable()` 추가 |

---

## 6. 데이터 요구사항

### 번들 내장 정적 파일

| 파일 | 출처 | 크기 (예상) | 갱신 주기 |
|------|------|------------|----------|
| `bus_stops_seoul.json` | [OA-15067](https://data.seoul.go.kr/dataList/OA-15067/S/1/datasetView.do) | ~1MB | 분기 |
| `subway_stations_seoul.json` | [data.go.kr/15099316](https://www.data.go.kr/data/15099316/fileData.do) | ~50KB | 거의 변동 없음 |
| `subway_lines_seoul.json` | 위 좌표 기반 호선별 순서 정의 | ~20KB | 거의 변동 없음 |

**bus_stops_seoul.json 구조**
```json
[
  { "stId": "123456789", "arsId": "23456", "name": "강남역사거리", "lat": 37.497, "lng": 127.027 }
]
```

**subway_stations_seoul.json 구조**
```json
[
  { "stationCode": "0222", "name": "강남", "nameEn": "Gangnam", "lat": 37.497, "lng": 127.028,
    "lines": ["2호선", "신분당선"] }
]
```

**subway_lines_seoul.json 구조**
```json
{
  "2호선": { "color": "#00A84D", "stationCodes": ["0201","0202",...] },
  "신분당선": { "color": "#D31145", "stationCodes": [...] }
}
```

### API 런타임 데이터 (앱 실행 중 조회)

| 데이터 | API | 캐시 전략 |
|--------|-----|----------|
| 버스 실시간 도착 | `ws.bus.go.kr/getArrInfoByRoute` | 시트 오픈 시 1회, 새로고침 버튼으로 재조회 |
| 버스 노선 경유 정류소 | `ws.bus.go.kr/getStaionByRoute` | 노선 드로어 오픈 시 1회, 인메모리 캐시 |
| 버스 노선 폴리라인 | `ws.bus.go.kr/getRoutePath` | 노선 드로어 오픈 시 1회, 인메모리 캐시 |
| 버스 시간표 | `ws.bus.go.kr/getBustimeByStation` | 노선+요일 조합별 인메모리 캐시 |
| 지하철 실시간 도착 | `swopenAPI.seoul.go.kr/realtimeStationArrival` | 시트 오픈 시 1회, 새로고침 버튼으로 재조회 |
| 지하철 시간표 | 서울 열린데이터광장 OA-101 (`openapi.seoul.go.kr:8088`) | 역+방향+요일 조합별 인메모리 캐시 |

---

## 7. 정적 데이터 갱신 전략

### 개요

버스 정류장 / 지하철역 데이터는 자주 바뀌지 않지만 분기별 변경이 있으므로, **Firebase Remote Config + Firebase Storage** 기반으로 앱 업데이트 없이 갱신한다.

### Firebase 구성

**Remote Config 키**
```json
{
  "bus_stops_url": "https://storage.googleapis.com/.../bus_stops_seoul.json",
  "subway_stations_url": "https://storage.googleapis.com/.../subway_stations_seoul.json",
  "subway_lines_url": "https://storage.googleapis.com/.../subway_lines_seoul.json"
}
```

**Firebase Storage**: JSON 파일 보관 및 배포

### 갱신 흐름

```
최초 실행
  └─ Remote Config fetch → URL 확인
  └─ 파일 다운로드 → 로컬 저장 (App Support)
      └─ 실패 시 → 번들 JSON fallback 사용

이후 실행
  └─ 로컬 저장 파일 사용 (즉시 표시, 네트워크 요청 없음)

수동 갱신 (설정 화면 — 하루 1회 제한)
  └─ "지금 업데이트" 버튼 탭
      └─ Remote Config fetch → URL 확인 → 파일 다운로드 → 로컬 파일 교체
      └─ 완료: 마지막 업데이트 날짜 갱신
      └─ 실패: 에러 메시지 표시, 기존 파일 유지
      └─ 오늘 이미 업데이트한 경우: 버튼 비활성화
```

> 자동 갱신 없음 — 사용자가 명시적으로 업데이트할 때만 갱신

### 로컬 저장 구조

```
App Support/
  transit_data/
    bus_stops_seoul.json         ← 위치 데이터
    subway_stations_seoul.json   ← 위치 데이터
    subway_lines_seoul.json      ← 호선 순서/색상
    bus_timetable/               ← 버스 시간표 캐시
      {arsId}_{routeId}_{dayType}.json
    subway_timetable/            ← 지하철 시간표 캐시
      {stationCode}_{direction}_{dayType}.json
    last_updated.json            ← { "transit_data": "2026-05-31", "timetable": {...} }
```

### 시간표 캐시 전략

| 데이터 | 최초 조회 시점 | 캐시 | 수동 갱신 |
|--------|-------------|------|---------|
| 버스 시간표 | 시간표 드로어 최초 진입 시 | 디스크 영구 저장 | 설정 화면 |
| 지하철 시간표 | 시간표 드로어 최초 진입 시 | 디스크 영구 저장 | 설정 화면 |

- 한 번 받은 시간표는 수동 갱신 전까지 재사용
- 수동 갱신 시 모든 시간표 캐시 삭제 후 재조회

### 설정 화면 표시

```
지도 데이터
  버스 정류장    마지막 업데이트: 2026.05.31
  지하철역       마지막 업데이트: 2026.05.31
  시간표         마지막 업데이트: 2026.05.31

  [지금 업데이트]   ← 오늘 이미 업데이트 시 비활성화
```

### Fallback 우선순위 (위치 데이터)

```
1순위: App Support 로컬 파일
2순위: 번들 내장 JSON (앱 배포 시 포함된 초기 데이터)
```

### 개발자 데이터 업데이트 프로세스

```
1. 원본 파일 다운로드 (OA-15067 등)
2. JSON 변환 스크립트 실행
3. Firebase Storage 업로드 (URL 고정)
4. (필요 시) Firebase Remote Config URL 업데이트
```

### Firebase 도입 범위 (이번 피처)

| 서비스 | 용도 |
|--------|------|
| Firebase Remote Config | 데이터 다운로드 URL 관리 |
| Firebase Storage | JSON 파일 호스팅 |

> Analytics, Crashlytics 등 추가 Firebase 서비스는 별도 피처에서 도입

---

## 8. 비기능 요구사항

- **마커 줌 임계값**: 지하철 `latΔ ≤ 0.15`, 버스 `latΔ ≤ 0.03` (7,000개 성능 고려)
- **폴리라인 표시**: 노선 드로어가 열려 있는 동안만 유지, 닫힘 시 즉시 제거
- **recptnDt 보정**: 지하철 도착 시간 = `barvlDt - (now - recptnDt)`, 음수면 "곧 도착"
- **에러 처리**: API 응답 에러코드 파싱 (기존 SeoulAPIError 패턴 확장)
- **API 호출 제한**: 실시간 도착은 수동 새로고침으로만 재조회, 자동 폴링 없음
- **정적 데이터 로드 실패 시**: fallback → 번들 JSON 사용, 사용자에게 노출 안 함

---

## 9. 미결 사항

| 항목 | 내용 |
|------|------|
| **Firebase 프로젝트 설정** | GoogleService-Info.plist 추가, Remote Config + Storage 활성화 |
| **번들 초기 데이터 준비** | OA-15067, data.go.kr/15099316 파일 다운로드 → JSON 변환 스크립트 |
| **Firebase Storage 업로드** | 변환된 JSON 파일 업로드 + Remote Config 초기값 설정 |
| ~~KRIC API 키 발급~~ | 서울 열린데이터광장 OA-101로 대체 — 기존 키 재사용, 불필요 |
| 버스 API 키 발급 | ✅ 완료 (`BUS_API_KEY` Secrets.xcconfig 추가) |
| 지하철 노선 색상 코드 | 공식 색상 정의 파일 작성 필요 |
| 신분당선 등 비서울교통공사 노선 처리 | 실시간 도착 API 커버리지 확인 필요 |
