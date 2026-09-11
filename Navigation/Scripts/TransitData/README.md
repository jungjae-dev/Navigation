# TransitData — 버스 정류장 정적 데이터 변환

버스 정류장 정보를 원본 파일에서 JSON으로 변환하는 스크립트입니다.
생성된 JSON은 GitHub Gist에 업로드하여 앱이 최초 실행 시 다운로드합니다.

> 지하철 기능은 제거되었습니다. (환승역 표시 복잡도 등으로 미채택)
> 재도입 시 KRIC 전국도시철도역사정보 표준데이터를 참고하세요:
> `https://data.kric.go.kr/rips/dataset/download.file?type=filedata&id=32&operation=1`

---

## 폴더 구조

```
Scripts/TransitData/
├── README.md       — 이 문서
├── convert.py      — 버스 정류장 변환 스크립트
├── output/         — 변환된 JSON 파일 (Gist 업로드용)
│   ├── version.json
│   └── bus_stops_seoul.json
└── source/         — 원본 파일 보관 (gitignore 권장)
    └── 서울시버스정류소위치정보(YYYYMMDD).xlsx
```

---

## 원본 파일 출처

| 데이터 | 출처 | 비고 |
|--------|------|------|
| 버스 정류장 | [서울 열린데이터광장 OA-15067](https://data.seoul.go.kr/dataList/OA-15067/S/1/datasetView.do) | XLSX |

---

## 사용 방법

### 1. 의존성 설치 (최초 1회)

```bash
cd Scripts/TransitData
python3 -m venv venv
source venv/bin/activate
pip install openpyxl
```

### 2. 원본 파일 배치

`source/` 폴더에 원본 파일을 넣습니다.
파일명에 날짜가 포함되어 있으면 자동으로 버전으로 사용됩니다.

### 3. 변환 실행

```bash
python3 convert.py   # 버스 정류장 → output/bus_stops_seoul.json + version.json
```

---

## 데이터 갱신 방법

1. 원본 파일 최신 버전 다운로드 → `source/` 폴더에 교체
2. `python3 convert.py` 실행
3. `output/` 의 변경된 파일을 GitHub Gist에서 교체
4. 앱 설정 → **데이터 새로고침** (또는 앱 재설치)

> 앱은 실행 시 `version.json`을 확인하여 버전이 다르면 해당 파일만 다운로드합니다.

---

## GitHub Gist URL

Gist: https://gist.github.com/jungjae-dev/2d049aa1765d273905fa1a440e2b4bc6

| 파일 | Raw URL |
|------|---------|
| version.json | https://gist.githubusercontent.com/jungjae-dev/2d049aa1765d273905fa1a440e2b4bc6/raw/version.json |
| bus_stops_seoul.json | https://gist.githubusercontent.com/jungjae-dev/2d049aa1765d273905fa1a440e2b4bc6/raw/bus_stops_seoul.json |

> Gist에 남아있는 `subway_*.json`, `version.json`의 subway 항목은 앱이 더 이상 읽지 않습니다. 정리하려면 Gist에서 제거하세요.

---

## JSON 구조

### version.json

```json
{
  "busStops": "20260506"
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
