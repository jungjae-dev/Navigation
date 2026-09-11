# 버스/지하철 정적 데이터 파이프라인

> 작성일: 2026-06-03
> ⚠️ 이 문서의 파일 배치(같은 폴더의 xlsx·output/)는 작성 당시 기준이다. 현행 파이프라인 정본은
> `Navigation/Scripts/TransitData/`(README.md에 출처·Gist·재생성 방법) — 지하철은 이후 앱에서 제거됨.

---

## 개요

버스 정류장, 지하철역, 지하철 호선 정보는 자주 변경되지 않는 정적 데이터입니다.  
매번 API를 호출하는 대신 JSON 파일로 변환하여 배포합니다.

---

## 데이터 흐름

```
원본 파일 (CSV/XLSX)
    │
    ▼
convert.py  ← 변환 스크립트
    │
    ▼
output/ JSON 파일 4개
    │
    ▼
GitHub Gist (public) 업로드
    │
    ▼
앱 최초 실행 시 다운로드 → 앱 Documents에 캐시
    │
    ▼
이후 실행: 캐시 사용 (version.json으로 최신 여부 확인)
```

---

## 원본 데이터 출처

| 파일 | 출처 | 갱신 주기 |
|------|------|-----------|
| 버스 정류장 | [서울 열린데이터광장 OA-15067](https://data.seoul.go.kr/dataList/OA-15067/S/1/datasetView.do) | 비정기 |
| 지하철역 좌표 | [data.go.kr/15099316](https://www.data.go.kr/data/15099316/fileData.do) | 비정기 |

---

## 변환 스크립트

### 실행 방법

```bash
# 의존성 설치 (최초 1회)
python3 -m venv venv
source venv/bin/activate
pip install openpyxl

# 변환 실행
python3 convert.py
```

### 입력 파일 위치

`convert.py`와 같은 폴더에 아래 파일이 있어야 합니다:

```
260530_bus/
├── 서울시버스정류소위치정보(YYYYMMDD).xlsx
├── 서울교통공사_1_8호선 역사 좌표(위경도) 정보_YYYYMMDD.csv
└── convert.py
```

### 출력 파일

```
260530_bus/output/
├── bus_stops_seoul.json       — 버스 정류장
├── subway_stations_seoul.json — 지하철역
├── subway_lines_seoul.json    — 호선 색상 + 역 순서
└── version.json               — 각 파일 버전
```

---

## JSON 파일 구조

### version.json

앱이 최초로 가져오는 파일. 버전 비교 후 필요한 파일만 다운로드.

```json
{
  "busStops": "20260506",
  "subwayStations": "20250814",
  "subwayLines": "20260603"
}
```

### bus_stops_seoul.json

```json
{
  "version": "20260506",
  "updatedAt": "2026-05-06",
  "count": 11250,
  "data": [
    { "stId": "123000689", "arsId": "00001", "name": "한강버스.잠실선착장", "lat": 37.518944, "lng": 127.084778 }
  ]
}
```

### subway_stations_seoul.json

```json
{
  "version": "20250814",
  "updatedAt": "2025-08-14",
  "count": 276,
  "data": [
    { "stationCode": "0222", "name": "강남", "lat": 37.4979, "lng": 127.0276, "lines": ["2호선", "신분당선"] }
  ]
}
```

### subway_lines_seoul.json

```json
{
  "version": "20260603",
  "updatedAt": "2026-06-03",
  "data": {
    "2호선": { "color": "#00A84D", "circular": true, "stationCodes": ["0201", "0202", ...] }
  }
}
```

---

## GitHub Gist 배포

### 최초 배포

1. [gist.github.com](https://gist.github.com) 접속
2. `output/` 폴더의 파일 4개 업로드 (**Create public gist**)
3. 각 파일의 **Raw** URL 확인

### Gist Raw URL 형식

```
https://gist.githubusercontent.com/{username}/{gist-id}/raw/{파일명}
```

> ⚠️ Raw URL에 commit hash가 포함된 경우 파일 수정 시 URL이 바뀜.  
> commit hash 없는 URL 사용: `.../raw/{파일명}` (항상 최신 버전)

### 데이터 갱신 방법

1. 원본 파일 최신 버전 다운로드
2. `python3 convert.py` 실행
3. Gist에서 해당 파일 내용 교체
4. 앱 설정 → 데이터 새로고침 (또는 앱 재설치)

---

## 앱 내 동작

### 최초 실행

1. `version.json` 다운로드
2. 로컬 캐시 버전과 비교
3. 버전이 다른 파일만 다운로드 → `Documents/TransitData/`에 저장

### 이후 실행

- 로컬 캐시 파일 사용
- 설정 화면에서 수동 새로고침 가능 (하루 1회 제한)
- 마지막 업데이트 날짜 설정 화면에 표시

---

## Gist URL 목록 (배포 후 기록)

| 파일 | Raw URL |
|------|---------|
| version.json | (업로드 후 기록) |
| bus_stops_seoul.json | (업로드 후 기록) |
| subway_stations_seoul.json | (업로드 후 기록) |
| subway_lines_seoul.json | (업로드 후 기록) |

> 이 URL들은 앱 코드에 하드코딩 또는 Remote Config에 등록.
