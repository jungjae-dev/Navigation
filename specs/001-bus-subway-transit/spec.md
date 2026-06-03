# Feature Specification: 버스/지하철 대중교통 기능

**Feature Branch**: `001-bus-subway-transit`

**Created**: 2026-06-03

**Status**: Draft

---

## 현황 (Pre-conditions)

아래 항목은 구현 시작 전 이미 완료된 상태임.

| 항목 | 상태 | 비고 |
|------|------|------|
| BUS_API_KEY | ✅ 완료 | 공공데이터포털 ws.bus.go.kr |
| SEOUL_OPEN_API_KEY | ✅ 완료 | 기존 키 재사용 (실시간 도착 + OA-101 시간표) |
| Firebase SPM + AppDelegate | ✅ 완료 | FirebaseAnalytics, Crashlytics, RemoteConfig |
| GoogleService-Info.plist | ✅ 완료 | 프로젝트 포함 |
| 정적 데이터 JSON 4개 | ✅ 완료 | GitHub Gist 업로드 완료 |
| 버스/지하철 Swift 코드 | ❌ 미구현 | 이 feature에서 구현 |

**Gist URL**: https://gist.github.com/jungjae-dev/2d049aa1765d273905fa1a440e2b4bc6

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 지도에서 버스/지하철 레이어 표시 (Priority: P1)

사용자가 홈 화면에서 POI 레이어 버튼을 탭하면 따릉이/버스/지하철 토글 팝업이 나타난다. 버스 또는 지하철을 켜면 지도에 해당 정류장/역 마커가 표시된다.

**Why this priority**: 다른 모든 기능의 진입점. 마커 없이는 상세/노선/시간표 기능이 의미 없음.

**Independent Test**: 버스 레이어를 켜면 지도에 버스 정류장 마커가 나타남.

**Acceptance Scenarios**:

1. **Given** 앱 실행 후 홈 화면, **When** POI 레이어 버튼 탭, **Then** 따릉이/버스/지하철 토글이 있는 팝업 표시
2. **Given** 팝업에서 버스 ON, **When** 충분히 줌인된 상태, **Then** 버스 정류장 마커 표시
3. **Given** 팝업에서 지하철 ON, **When** 지도 확인, **Then** 지하철역 마커 표시 (환승역은 복합 색상)
4. **Given** 줌 아웃 상태, **When** 버스 레이어 ON, **Then** 마커 숨김 (버스: latΔ ≤ 0.03, 지하철: latΔ ≤ 0.15)
5. **Given** 오프라인 상태 첫 실행, **When** 앱 시작, **Then** 번들 fallback JSON으로 마커 표시

---

### User Story 2 - 버스 정류장 상세 + 실시간 도착 (Priority: P2)

사용자가 버스 정류장 마커를 탭하면 해당 정류소의 경유 노선 목록과 각 노선의 실시간 도착 정보가 시트로 표시된다.

**Why this priority**: 버스 이용의 핵심 정보.

**Independent Test**: 마커 탭 → 시트 열림 → 도착 정보 표시.

**Acceptance Scenarios**:

1. **Given** 버스 마커 탭, **When** 시트 열림, **Then** 경유 노선 목록과 실시간 도착 정보 표시
2. **Given** 시트 내 새로고침 버튼, **When** 탭, **Then** 실시간 도착 재조회
3. **Given** 운행 종료 노선, **When** 표시, **Then** "운행 종료" 메시지 표시
4. **Given** 도보 길찾기 버튼, **When** 탭, **Then** 해당 정류소까지 도보 경로 진입

---

### User Story 3 - 버스 노선 상세 (Priority: P3)

사용자가 버스 도착 정보에서 특정 노선을 탭하면 지도에 노선 폴리라인이 그려지고 경유 정류소 목록이 드로어로 표시된다.

**Why this priority**: 노선 파악은 도착 정보 확인 다음 단계.

**Independent Test**: 노선 탭 → 폴리라인 + 정류소 드로어 표시.

**Acceptance Scenarios**:

1. **Given** 버스 도착 시트에서 노선 탭, **When** 드로어 열림, **Then** 지도에 폴리라인 + 경유 정류소 목록
2. **Given** 노선 드로어의 정류소 탭, **When** 탭, **Then** 지도가 해당 정류소로 이동 (드로어 유지)
3. **Given** 지도에서 다른 정류소 마커 탭, **When** 탭, **Then** 노선 드로어 닫힘 + 새 정류소 상세로 전환
4. **Given** 스택 내 정류소 상세 + 노선 드로어, **When** 새 정류소/노선 진입, **Then** 각각 1개만 유지

---

### User Story 4 - 버스 시간표 (Priority: P4)

사용자가 버스 정류소 상세에서 시간표 버튼을 탭하면 노선/요일별 시간표가 표시된다.

**Acceptance Scenarios**:

1. **Given** 시간표 버튼 탭, **When** 드로어 열림, **Then** 노선 선택 + 평일/토/일 탭 + 시간 그리드
2. **Given** 같은 노선+요일 재선택, **When** 표시, **Then** API 재호출 없이 캐시 사용

---

### User Story 5 - 지하철역 상세 + 실시간 도착 (Priority: P5)

사용자가 지하철역 마커를 탭하면 호선별 상/하행 실시간 도착 정보가 표시된다.

**Acceptance Scenarios**:

1. **Given** 지하철 마커 탭, **When** 시트 열림, **Then** 호선별 섹션 분리, 상/하행 각 2개 도착 표시
2. **Given** 환승역, **When** 표시, **Then** 각 호선별 섹션 분리
3. **Given** 도보 길찾기 버튼, **When** 탭, **Then** 해당 역까지 도보 경로 진입

---

### User Story 6 - 지하철 노선 상세 (Priority: P6)

사용자가 지하철역 상세에서 호선을 탭하면 지도에 노선 전체가 표시되고 역 목록이 드로어로 나타난다.

**Acceptance Scenarios**:

1. **Given** 호선 탭, **When** 드로어 열림, **Then** 지도에 호선 색상 폴리라인 + 역 목록
2. **Given** 2호선, **When** 표시, **Then** 순환선 폐곡선으로 표시
3. **Given** 역 목록에서 역 탭, **When** 탭, **Then** 지도 카메라 이동 (드로어 유지)

---

### User Story 7 - 지하철 시간표 (Priority: P7)

**Acceptance Scenarios**:

1. **Given** 시간표 버튼 탭, **When** 드로어 열림, **Then** 호선/방향/요일 선택 + 시간 그리드
2. **Given** 캐시 존재, **When** 같은 조건 재조회, **Then** API 재호출 없이 캐시 사용

---

### User Story 8 - 설정 화면 데이터 갱신 (Priority: P8)

사용자가 설정 화면에서 데이터 새로고침 버튼을 탭하면 최신 버스/지하철 데이터를 다운로드한다. 하루 1회로 제한.

**Acceptance Scenarios**:

1. **Given** 설정 화면, **When** 새로고침 버튼 탭, **Then** Gist에서 version.json 확인 → 변경된 파일만 다운로드
2. **Given** 오늘 이미 갱신, **When** 버튼 탭, **Then** 버튼 비활성화 + "오늘 업데이트됨" 표시
3. **Given** 갱신 완료, **When** 화면 확인, **Then** 마지막 업데이트 날짜 표시

---

### Edge Cases

- 네트워크 없는 상태에서 첫 실행 → 번들 내장 fallback JSON 사용
- version.json 다운로드 실패 → 기존 캐시 유지, 에러 무시
- 버스 API 타임아웃 → 사용자에게 재시도 안내
- 환승역 중복 표시 없음 (동일 stationCode로 병합)

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 앱은 시작 시 Gist의 version.json을 조회하고, 로컬 캐시 버전과 다른 경우에만 해당 파일을 다운로드해야 한다.
- **FR-002**: 다운로드된 데이터는 `Documents/TransitData/`에 저장되어야 하며, 오프라인 시 사용 가능해야 한다.
- **FR-003**: 번들에 fallback JSON이 포함되어야 하며, 네트워크 없이도 기본 동작해야 한다.
- **FR-004**: POI 레이어 팝업은 따릉이/버스/지하철 토글을 포함하며, 기존 따릉이 토글 버튼을 대체해야 한다.
- **FR-005**: 버스 정류장 마커는 줌 레벨 latΔ ≤ 0.03 이하에서만 표시되어야 한다.
- **FR-006**: 지하철역 마커는 줌 레벨 latΔ ≤ 0.15 이하에서만 표시되어야 한다.
- **FR-007**: 실시간 버스 도착 정보는 ws.bus.go.kr API를 통해 조회되어야 한다.
- **FR-008**: 실시간 지하철 도착 정보는 swopenAPI.seoul.go.kr API를 통해 조회되어야 한다.
- **FR-009**: 지하철 시간표는 openapi.seoul.go.kr:8088 (OA-101)을 통해 조회되며, 디스크에 영구 캐시되어야 한다.
- **FR-010**: 버스 시간표는 디스크에 영구 캐시되어야 하며, 수동 갱신 시 초기화되어야 한다.
- **FR-011**: 드로어 스택은 정류소 상세 1개 + 노선 상세 1개로 제한되어야 한다.
- **FR-012**: 설정 화면에서 데이터 수동 갱신이 가능하며, 하루 1회로 제한되어야 한다.

### Key Entities

- **BusStop**: stId, arsId, name, coordinate — 버스 정류소
- **SubwayStation**: stationCode, name, coordinate, lines[] — 지하철역 (환승역 포함)
- **SubwayLines**: 호선별 color, stationCodes[], circular — 노선 정보
- **BusArrival**: routeId, routeName, direction, firstArrivalMessage, secondArrivalMessage, routeType
- **SubwayArrival**: lineName, direction, destination, arrivalMessage, arrivalCode
- **TransitDataVersion**: busStops, subwayStations, subwayLines — 버전 정보

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 앱 시작 후 버스/지하철 마커가 3초 이내에 지도에 표시된다.
- **SC-002**: 버스 정류소 마커 탭 후 실시간 도착 정보가 5초 이내에 표시된다.
- **SC-003**: 오프라인 상태에서도 마커 표시가 동작한다 (캐시 또는 번들 fallback).
- **SC-004**: 드로어 스택이 최대 2단계를 초과하지 않는다.
- **SC-005**: 시간표 재조회 시 캐시가 있으면 네트워크 호출이 발생하지 않는다.
- **SC-006**: 데이터 갱신 후 마지막 업데이트 날짜가 설정 화면에 반영된다.

---

## Assumptions

- 서울 대중교통 데이터만 지원 (1단계 서울 한정).
- 정적 데이터(정류소/역 위치)는 GitHub Gist를 통해 배포되며, 앱 업데이트 없이 갱신 가능.
- 실시간 도착 정보는 최초 1회 조회 후 새로고침 버튼으로만 갱신 (자동 폴링 없음).
- 도보 경로 안내는 기존 RoutePreview 도보 모드를 재사용.
- CarPlay 화면은 이 feature 범위에 포함되지 않음.
- Firebase Storage는 Spark 플랜 제한으로 미사용, GitHub Gist 대체.
