# 버스/지하철 API 조사 결과

> 작성일: 2026-05-30  
> 범위: 서울 (1단계), 전국 (향후 확장)

---

## 목차

1. [API 키 현황](#1-api-키-현황)
2. [서울 버스 API](#2-서울-버스-api)
3. [서울 지하철 API](#3-서울-지하철-api)
4. [전국 버스 API — TAGO](#4-전국-버스-api--tago)
5. [전국 지하철 API](#5-전국-지하철-api)
6. [호출 제한 및 정책](#6-호출-제한-및-정책)
7. [API 비교 요약](#7-api-비교-요약)
8. [1단계 구현 권장 조합](#8-1단계-구현-권장-조합)

---

## 1. API 키 현황

| 키 | 용도 | 발급처 | 상태 |
|----|------|--------|------|
| 서울 열린데이터광장 키 | 따릉이, 지하철 실시간 도착, 지하철 역명 검색 | [data.seoul.go.kr](https://data.seoul.go.kr) | ✅ 기존 보유 |
| 버스 API 키 | 서울 버스 정류소, 도착, 노선 전체 | [api.bus.go.kr](http://api.bus.go.kr) | ❌ 신규 발급 필요 |
| t-data 키 | 지하철역 좌표 (번들 내장으로 대체 가능) | [t-data.seoul.go.kr](https://t-data.seoul.go.kr) | ⚠️ 번들 대체 시 불필요 |
| TAGO 키 | 전국 버스 정류소, 도착, 노선 | [data.go.kr](https://www.data.go.kr) | ❌ 전국 확장 시 필요 |

---

## 2. 서울 버스 API

**호스트**: `http://ws.bus.go.kr/api/rest/`  
**인증**: `serviceKey` 쿼리 파라미터 (api.bus.go.kr 공유자원포털에서 발급)  
**응답 포맷**: XML 기본, JSON 가능  
**영문명**: ❌ 없음  
**상업적 이용**: ❌ 비상업적만 허용  

---

### 2-1. 정류소 정보

#### 정류소명 검색 — `getStationByName`

```
GET http://ws.bus.go.kr/api/rest/stationinfo/getStationByName
  ?serviceKey={KEY}
  &stSrch={정류소명}
```

| 필드 | 타입 | 설명 |
|------|------|------|
| `stId` | String(9) | 정류소 고유 ID |
| `stNm` | String | 정류소명 (한국어) |
| `arsId` | String(5) | 정류소 번호 (표출번호, BIS ID) |
| `tmX` | Number | X좌표 ⚠️ **TM 좌표계** (WGS84 아님, 변환 필요) |
| `tmY` | Number | Y좌표 ⚠️ **TM 좌표계** |
| `posX` | Number | GRS80 X좌표 (optional) |
| `posY` | Number | GRS80 Y좌표 (optional) |

> ⚠️ `tmX`/`tmY`는 WGS84(위경도)가 아닌 TM 좌표계. MapKit에서 직접 사용 불가, 좌표 변환 필요.  
> WGS84 좌표가 필요하면 `getStaionByRoute` 응답의 `gpsX`/`gpsY` 활용 권장.

#### arsId로 정류소 상세 + 경유 노선 목록 — `getStationByUid`

```
GET http://ws.bus.go.kr/api/rest/stationinfo/getStationByUid
  ?serviceKey={KEY}
  &arsId={arsId}
```

정류소 기본 정보 + 해당 정류소를 경유하는 모든 노선의 도착 정보 통합 반환.

#### 정류소별 경유 노선 목록 — `getRouteByStation`

```
GET http://ws.bus.go.kr/api/rest/stationinfo/getRouteByStation
  ?serviceKey={KEY}
  &arsId={arsId}
```

| 필드 | 타입 | 설명 |
|------|------|------|
| `busRouteId` | String(9) | 노선 고유 ID |
| `busRouteNm` | String | 노선 번호/명칭 |
| `routeType` | String(1) | 노선 유형 코드 (아래 참조) |
| `stBegin` | String | 기점 정류소명 |
| `stEnd` | String | 종점 정류소명 |
| `term` | Number | 배차 간격 (분) |
| `firstTm` | String | 첫차 시간 |
| `lastTm` | String | 막차 시간 |

---

### 2-2. 노선 정보

#### 노선 목록 조회 — `getBusRouteList`

```
GET http://ws.bus.go.kr/api/rest/busRouteInfo/getBusRouteList
  ?serviceKey={KEY}
  &strSrch={노선번호}     ← 빈 문자열이면 전체 반환
```

| 필드 | 타입 | 설명 |
|------|------|------|
| `busRouteId` | String(9) | 노선 고유 ID |
| `busRouteNm` | String | 노선 번호/명칭 |
| `routeType` | String(1) | 노선 유형 코드 |
| `stStationNm` | String | 기점 정류소명 |
| `edStationNm` | String | 종점 정류소명 |
| `term` | Number | 배차 간격 (분) |
| `firstBusTm` | String | 첫차 시간 |
| `lastBusTm` | String | 막차 시간 |
| `corpNm` | String | 운수 회사명 |

**노선 유형 코드 (`routeType`)**

| 코드 | 유형 |
|------|------|
| 1 | 공항 |
| 2 | 마을 |
| 3 | 간선 |
| 4 | 지선 |
| 5 | 순환 |
| 6 | 광역 |
| 7 | 인천 |
| 8 | 경기 |
| 9 | 폐지예정 |
| 0 | 제한 없음 |

#### 노선별 경유 정류소 목록 — `getStaionByRoute`

```
GET http://ws.bus.go.kr/api/rest/busRouteInfo/getStaionByRoute
  ?serviceKey={KEY}
  &busRouteId={busRouteId}
```

> ⚠️ URL에 오타 그대로 (`Station` → `Staion`)

| 필드 | 타입 | 설명 |
|------|------|------|
| `seq` | Number | 정류소 순서 번호 |
| `stationNm` | String | 정류소명 (한국어) |
| `stationNo` | String | 정류소 고유번호 (arsId) |
| `gpsX` | Number | **WGS84 경도** ✅ MapKit 직접 사용 가능 |
| `gpsY` | Number | **WGS84 위도** ✅ |
| `direction` | String | 진행 방향 (종착 방향 표시) |
| `beginTm` | String | 해당 정류소 첫차 시각 |
| `lastTm` | String | 해당 정류소 막차 시각 |
| `transYn` | String | 회차지 여부 |

#### 노선 경로 폴리라인 — `getRoutePath`

```
GET http://ws.bus.go.kr/api/rest/busRouteInfo/getRoutePath
  ?serviceKey={KEY}
  &busRouteId={busRouteId}
```

`gpsX`/`gpsY` 좌표 배열(itemList)로 노선 shape 반환. 지도에 노선 선 그리기에 사용.

---

### 2-3. 실시간 도착 정보

#### 정류소 + 노선 기준 도착 정보 — `getArrInfoByRoute`

```
GET http://ws.bus.go.kr/api/rest/arrive/getArrInfoByRoute
  ?serviceKey={KEY}
  &stId={stId}
  &busRouteId={busRouteId}
  &ord={정류소순번}
```

#### 노선의 전체 정류소 도착 정보 — `getArrInfoByRouteAll`

```
GET http://ws.bus.go.kr/api/rest/arrive/getArrInfoByRouteAll
  ?serviceKey={KEY}
  &busRouteId={busRouteId}
```

**도착 정보 응답 주요 필드 (itemList)**

| 필드 | 타입 | 설명 |
|------|------|------|
| `arrmsg1` | String | **첫 번째 도착 메시지** (예: "3분후 [5번째 전]") |
| `arrmsg2` | String | **두 번째 도착 메시지** |
| `exps1` | Number | 첫 번째 도착 예정 시간 **(초)** |
| `exps2` | Number | 두 번째 도착 예정 시간 (초) |
| `plainNo1` | String | 첫 번째 도착 차량 번호판 |
| `plainNo2` | String | 두 번째 도착 차량 번호판 |
| `busType1` | String(1) | 첫 번째 버스 유형 (0:일반, 1:저상, 2:굴절) |
| `busType2` | String(1) | 두 번째 버스 유형 |
| `isLast1` | String(1) | 막차 여부 (0:아님, 1:막차) |
| `full1` | String(1) | 만차 여부 |
| `routeType` | String(1) | 노선 유형 |
| `busRouteNm` | String | 노선명 |
| `mkTm` | String | 데이터 제공 시각 |
| `firstTm` | String | 첫차 시간 |
| `lastTm` | String | 막차 시간 |
| `term` | Number | 배차 간격 (분) |

---

## 3. 서울 지하철 API

**기존 키 재사용 가능** — 서울 열린데이터광장 인증키

---

### 3-1. 역 정보

#### 역명으로 역 + 호선 검색 — OA-121

```
GET http://openapi.seoul.go.kr:8088/{KEY}/json/SearchSTNBySubwayLineInfo/1/100/{역명}
```

| 필드 | 설명 |
|------|------|
| 호선 | 호선 번호 (예: "2호선") |
| 외부코드 | 외부 역 코드 (고유역번호) — 좌표 데이터와 조인 키 |
| 전철역코드 | 내부 역 코드 |
| 역명 | 한국어 역명 |
| **영문역명** | ✅ 영문 역명 |
| 중문역명 | 중국어 역명 |
| 일문역명 | 일본어 역명 |

> 환승역은 호선 수만큼 여러 행 반환 (예: 강남역 → 2호선, 신분당선 2행)

#### 호선별 역 목록 — OA-15442

```
GET http://openapi.seoul.go.kr:8088/{KEY}/json/SearchInfoBySubwayLineInfo/1/100/{호선명}
```

응답 필드 동일 (OA-121과 동일 구조). `외부코드` 기준으로 좌표 파일과 조인.

> 커버리지: 서울교통공사 운영 1~8호선, 9호선 2~3단계(언주~중앙보훈병원)  
> 미포함: 공항철도, 신분당선, GTX 등 타 운영사 노선

#### 지하철역 좌표 — 번들 내장 (권장)

- 출처: [data.go.kr/data/15099316](https://www.data.go.kr/data/15099316/fileData.do) — 서울교통공사 1~8호선 역사 좌표
- 총 276개 역, 필드: `호선`, `고유역번호(외부역코드)`, `역명`, `위도`, `경도`
- 역 위치는 거의 변하지 않으므로 앱 번들 내장 후 `외부코드`로 조인

대안 (API): t-data.seoul.go.kr — `TaimsKsccDvSubwayStationGeom` (별도 키 필요)

---

### 3-2. 실시간 도착 정보

#### 역별 실시간 열차 도착 — OA-12764

```
GET http://swopenAPI.seoul.go.kr/api/subway/{KEY}/json/realtimeStationArrival/0/20/{역명}
```

- `{역명}`: URL 인코딩된 한글 역명 (예: `강남`, `서울역`)
- 범위 파라미터: `0/20` → 0번째부터 20건 (최대 1,000건/호출)
- 커버리지: 서울 1~9호선 (광명, 서동탄, 춘천 등 서울 外 구간 미제공)

**응답 구조**

```json
{
  "errorMessage": { "status": 200, "code": "INFO-000", "message": "정상 처리되었습니다" },
  "realtimeArrivalList": [ { ... } ]
}
```

**realtimeArrivalList 필드**

| 필드 | 설명 |
|------|------|
| `subwayId` | 호선 ID (예: "1002" = 2호선) |
| `subwayNm` | 호선명 |
| `updnLine` | 방향 (상행/하행/외선/내선) |
| `trainLineNm` | **열차 행선지** (예: "성수행", "외선순환") |
| `barvlDt` | **도착까지 남은 시간 (초)** — `recptnDt` 보정 필요 |
| `arvlMsg2` | **도착 메시지** (예: "2번째 전역 출발", "잠시후 도착") |
| `arvlMsg3` | **현재 위치 역명** |
| `arvlCd` | 도착 코드 (0:진입, 1:도착, 2:출발, 3:전역출발, 4:전전역출발, 5:전전역진입, 99:운행중) |
| `btrainSttus` | 열차 종류 (급행/일반) |
| `btrainNo` | 열차 번호 |
| `bstatnNm` | 종착역명 |
| `recptnDt` | **데이터 생성 시각** (형식: "2026-05-30 14:30:00.0") |
| `statnId` | 현재 역 ID |
| `statnNm` | 현재 역명 |

**⚠️ recptnDt 시간 보정 필수**

```
보정된 도착 시간(초) = barvlDt - (현재시각 - recptnDt 파싱한 시각)
```

서버에서 열차 위치 데이터를 생성한 시각과 앱에서 수신한 시각 사이의 차이를 `barvlDt`에서 차감해야 실제 남은 시간이 됨.

#### 열차 실시간 위치 — OA-12601

```
GET http://swopenAPI.seoul.go.kr/api/subway/{KEY}/json/realtimePosition/0/100/{호선명}
```

현재 운행 중인 열차 위치(역 간 구간), 열차 번호, 상하행 구분, 종착역 반환.

---

## 4. 전국 버스 API — TAGO

**호스트**: `http://apis.data.go.kr/1613000/`  
**인증**: `serviceKey` 쿼리 파라미터 (data.go.kr에서 발급)  
**응답 포맷**: XML 기본, `_type=json`으로 JSON 가능  
**커버리지**: 전국 (BIS 연계 지자체만 실시간 가능 — 서울·6대 광역시 OK, 군 단위 미보장)  
**영문명**: ❌ 없음  
**일일 한도**: 10,000건 (개발 계정)

---

### 4-1. 정류소 정보

#### 좌표 기반 주변 정류소 검색

```
GET http://apis.data.go.kr/1613000/BusSttnInfoInqireService/getCrdntPrxmtSttnList
  ?serviceKey={KEY}
  &gpsLati={위도}
  &gpsLong={경도}
  &_type=json
```

- 검색 반경: **500m 고정**
- `cityCode` 파라미터 없이도 전국 검색 가능

| 필드 | 설명 |
|------|------|
| `nodeid` | 정류소 고유 ID |
| `nodenm` | 정류소명 (한국어) |
| `gpslati` | **WGS84 위도** ✅ |
| `gpslong` | **WGS84 경도** ✅ |
| `citycode` | 도시 코드 |

#### 정적 파일: 전국 버스정류장 좌표

- 출처: [data.go.kr/data/15067528](https://www.data.go.kr/data/15067528/fileData.do)
- 전국 206,022개 정류소, 연 1회 갱신
- 앱 번들 내장 또는 초기 다운로드 후 캐싱 가능

---

### 4-2. 노선 정보

#### 노선 기본 정보 조회

```
GET http://apis.data.go.kr/1613000/BusRouteInfoInqireService/getRouteInfoIem
  ?serviceKey={KEY}
  &cityCode={도시코드}
  &routeId={노선ID}
  &_type=json
```

| 필드 | 설명 |
|------|------|
| `routeno` | 노선 번호 |
| `startnodenm` | 기점 정류소명 |
| `endnodenm` | 종점 정류소명 |
| `intervaltime` | 배차 간격 (평일, 분) |
| `intervaltimeSat` | 배차 간격 (토요일) |
| `intervaltimeSun` | 배차 간격 (일요일/공휴일) |
| `startvrshtm` | 첫차 시간 |
| `endvrshtm` | 막차 시간 |

#### 도시 코드 목록 조회

```
GET http://apis.data.go.kr/1613000/BusRouteInfoInqireService/getCtyCodeList
  ?serviceKey={KEY}
  &_type=json
```

---

### 4-3. 실시간 도착 정보

```
GET http://apis.data.go.kr/1613000/ArvlInfoInqireService/getSttnAcctoArvlPrearngeInfoList
  ?serviceKey={KEY}
  &cityCode={도시코드}
  &nodeId={정류소ID}
  &_type=json
```

| 필드 | 설명 |
|------|------|
| `routeno` | 노선 번호 |
| `arrtime` | **도착 예정 시간 (초)** |
| `arrprevstationcnt` | **남은 정류소 수** |
| `vehicletp` | 버스 유형 |

---

## 5. 전국 지하철 API

### 전국 단일 실시간 API: 없음

지하철 실시간 도착은 도시별로 분산:

| 도시 | API | 키 |
|------|-----|-----|
| 서울 | data.seoul.go.kr OA-12764 | 서울 열린데이터광장 |
| 부산 | 부산광역시 데이터포털 | 별도 발급 |
| 대구 | 대구광역시 데이터포털 | 별도 발급 |
| 인천 | 인천광역시 데이터포털 | 별도 발급 |
| 광주 | 광주광역시 데이터포털 | 별도 발급 |
| 대전 | 대전광역시 데이터포털 | 별도 발급 |

### KRIC 레일포털 (전국 도시철도)

**호스트**: `https://openapi.kric.go.kr/openapi/`  
**용도**: 역 정보, 시간표, 편의시설, 혼잡도 통계  
**⚠️ 실시간 도착 정보 미제공** — 정적 시간표 중심

```
GET https://openapi.kric.go.kr/openapi/convenientInfo/stPlf
  ?serviceKey={KEY}
  &format=json
```

---

## 6. 호출 제한 및 정책

| API | 기본 일일 한도 | 확장 방법 | 비고 |
|-----|--------------|-----------|------|
| 서울 열린데이터광장 (일반) | **무제한** | — | |
| 서울 지하철 실시간 (`swopenapi`) | **1,000건/일** | 활용사례 등록 후 무제한 | 앱 출시 후 신청 가능 |
| 서울 버스 (`ws.bus.go.kr`) | **1,000건/일** | 활용사례 등록 후 증량 | 비상업적만 허용 |
| TAGO (`apis.data.go.kr`) | **10,000건/일** | 활용사례 등록 후 증량 | |
| t-data.seoul.go.kr | **1,000건/일** | 관리자 승인 시 100,000건/일 | |

**공통 주의사항**
- 모든 서울 API는 HTTP 429 미사용, 응답 바디 에러코드로 한도 초과 반환
- 실시간 데이터 갱신 주기: 버스 약 30초, 지하철 약 15~30초
- 갱신 주기 이내 반복 호출은 앱 내 캐싱으로 방지 권장

---

## 7. API 비교 요약

### 정류소/역 위치

| 항목 | API | WGS84 좌표 | 영문명 | 키 |
|------|-----|-----------|--------|-----|
| 서울 버스 정류소 (검색) | `ws.bus.go.kr/getStationByName` | ⚠️ TM 좌표 (변환 필요) | ❌ | 버스 키 |
| 서울 버스 정류소 (노선별) | `ws.bus.go.kr/getStaionByRoute` | ✅ gpsX/gpsY | ❌ | 버스 키 |
| 서울 지하철역 | OA-121 / OA-15442 | ❌ (번들 별도) | ✅ | 기존 키 |
| 서울 지하철역 좌표 | 파일 번들 내장 | ✅ | ❌ | 불필요 |
| 전국 버스 정류소 | TAGO `getCrdntPrxmtSttnList` | ✅ | ❌ | TAGO 키 |

### 실시간 도착

| 항목 | API | 도착 시간 형식 | 보정 필요 | 키 |
|------|-----|--------------|---------|-----|
| 서울 버스 도착 | `ws.bus.go.kr/getArrInfoByRoute` | 초 (`exps1`) + 메시지 | ❌ | 버스 키 |
| 서울 지하철 도착 | `swopenAPI/realtimeStationArrival` | 초 (`barvlDt`) + 메시지 | ✅ recptnDt 차감 | 기존 키 |
| 전국 버스 도착 | TAGO `getSttnAcctoArvlPrearngeInfoList` | 초 (`arrtime`) | ❌ | TAGO 키 |

### 노선 정보

| 항목 | API | 폴리라인 | 영문명 | 키 |
|------|-----|---------|--------|-----|
| 서울 버스 노선 목록 | `ws.bus.go.kr/getBusRouteList` | ❌ | ❌ | 버스 키 |
| 서울 버스 노선 경로 | `ws.bus.go.kr/getRoutePath` | ✅ gpsX/gpsY 배열 | — | 버스 키 |
| 서울 지하철 노선 | OA-15442 | ❌ (공식 API 없음) | ✅ 역명 영문 | 기존 키 |
| 전국 버스 노선 | TAGO `getRouteInfoIem` | ❌ | ❌ | TAGO 키 |

---

## 8. 1단계 구현 권장 조합

### 서울 버스

```
정류소 위치   →  ws.bus.go.kr/getStaionByRoute (WGS84 좌표 포함)
실시간 도착   →  ws.bus.go.kr/getArrInfoByRoute
노선 목록     →  ws.bus.go.kr/getBusRouteList
노선 폴리라인 →  ws.bus.go.kr/getRoutePath
```

필요 키: `api.bus.go.kr` 신규 발급 1개

### 서울 지하철

```
역 위치       →  번들 내장 JSON (data.go.kr/15099316 기반, 276개 역)
역명/호선     →  openapi.seoul.go.kr:8088/SearchSTNBySubwayLineInfo (기존 키)
실시간 도착   →  swopenAPI.seoul.go.kr/realtimeStationArrival (기존 키)
열차 위치     →  swopenAPI.seoul.go.kr/realtimePosition (기존 키)
```

필요 키: 기존 서울 열린데이터광장 키 재사용

### 향후 전국 확장

```
버스 정류소   →  TAGO getCrdntPrxmtSttnList (반경 500m)
버스 실시간   →  TAGO getSttnAcctoArvlPrearngeInfoList
지하철        →  도시별 개별 API 추가 (부산, 대구 등 순차 확장)
```

필요 키: TAGO (data.go.kr) 신규 발급 1개

---

## 참고 링크

- [서울 버스 공유자원포털 (키 발급)](http://api.bus.go.kr)
- [서울 버스 정류소 정보 조회](https://www.data.go.kr/data/15000303/openapi.do)
- [서울 버스 도착 정보 조회](https://www.data.go.kr/data/15000314/openapi.do)
- [서울 버스 노선 정보 조회](https://www.data.go.kr/data/15000193/openapi.do)
- [서울 지하철 실시간 도착 OA-12764](https://data.seoul.go.kr/dataList/OA-12764/F/1/datasetView.do)
- [서울 지하철 역명 검색 OA-121](https://data.seoul.go.kr/dataList/OA-121/S/1/datasetView.do)
- [서울 지하철 노선별 역 OA-15442](https://data.seoul.go.kr/dataList/OA-15442/S/1/datasetView.do)
- [서울 지하철역 좌표 파일 (data.go.kr)](https://www.data.go.kr/data/15099316/fileData.do)
- [TAGO 버스 도착 정보](https://www.data.go.kr/data/15098530/openapi.do)
- [TAGO 버스 정류소 정보](https://www.data.go.kr/data/15098534/openapi.do)
- [TAGO 버스 노선 정보](https://www.data.go.kr/data/15098529/openapi.do)
- [t-data 지하철역 좌표 API](https://t-data.seoul.go.kr/category/dataviewopenapi.do?data_id=1036)
- [KRIC 레일포털 Open API](https://data.kric.go.kr/rips/M_01_02/intro.do)
