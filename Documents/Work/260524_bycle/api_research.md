# 따릉이 API 조사 결과

> 작성일: 2026-05-24
> 목적: 서울시 공공자전거(따릉이) 관련 모든 API 조사 및 모바일 앱 적용 검토

---

## 1. 따릉이 관련 데이터셋 전체 목록

### 서울 열린데이터광장 (data.seoul.go.kr)

| 데이터셋 ID | 서비스명 | 유형 | 업데이트 주기 | 링크 |
|---|---|---|---|---|
| **OA-15493** | 공공자전거 실시간 대여정보 | 실시간 OpenAPI (JSON/XML) | 수시 (1~5분) | [열기](https://data.seoul.go.kr/dataList/OA-15493/A/1/datasetView.do) |
| **OA-13252** | 공공자전거 대여소 정보 | 파일 (CSV/XLSX) | 반기 | [열기](https://data.seoul.go.kr/dataList/OA-13252/F/1/datasetView.do) |
| **OA-21235** | 따릉이대여소 마스터 정보 (TOPIS) | DB / API | 수시 | [열기](https://data.seoul.go.kr/dataList/OA-21235/S/1/datasetView.do?tab=A) |
| **OA-15182** | 공공자전거 대여이력 정보 | 파일 (ZIP, 연도별) | 반기 | [열기](https://data.seoul.go.kr/dataList/OA-15182/F/1/datasetView.do) |
| **OA-14994** | 공공자전거 이용현황 (일별/시간별/월별) | 파일 (CSV/XLSX) | 반기 | [열기](https://data.seoul.go.kr/dataList/OA-14994/F/1/datasetView.do) |
| **OA-21229** | 대여소별 대여/반납 승객수 (5분 단위 OD) | 파일 | 일별 (D-5) | [열기](https://data.seoul.go.kr/dataList/OA-21229/F/1/datasetView.do) |
| **OA-22382** | 대여소별 대여가능 수량 (1시간 단위 스냅샷) | 파일/API | 시간별 | [열기](https://data.seoul.go.kr/dataList/OA-22382/F/1/datasetView.do) |
| **OA-15249** | 대여소별 이용정보 (월별) | 파일 | 월별 | [열기](https://data.seoul.go.kr/dataList/OA-15249/F/1/datasetView.do) |

### 공공데이터포털 (data.go.kr)

| 식별번호 | 서비스명 | 비고 | 링크 |
|---|---|---|---|
| 15077786 | 공공자전거 대여 이력 | OpenAPI | [열기](https://www.data.go.kr/data/15077786/openapi.do) |
| 15099365 | 따릉이대여소 마스터 정보 | 파일데이터 | [열기](https://www.data.go.kr/data/15099365/fileData.do) |
| 15051873 | 공공자전거 이용현황 | 파일데이터 | [열기](https://www.data.go.kr/data/15051873/fileData.do) |
| 15126330 | 서울시설공단 공공자전거 대여이력 정보 | OpenAPI | [열기](https://www.data.go.kr/data/15126330/openapi.do) |
| 3045310 | 서울시설공단 공공자전거 OpenAPI 묶음 (13건) | OpenAPI 모음 | [열기](https://www.data.go.kr/dataset/3045310/openapi.do) |

### 서울교통 빅데이터 플랫폼 (t-data.seoul.go.kr)

| ID | 서비스명 | 링크 |
|---|---|---|
| 1044 | 따릉이 운영 대여소 (API) | [열기](https://t-data.seoul.go.kr/dataprovide/trafficdataviewopenapi.do?data_id=1044) |

---

## 2. 핵심 API: 실시간 대여정보 (OA-15493) ⭐

모바일 앱에서 가장 중요한 API.

🔗 **데이터셋 페이지**: [data.seoul.go.kr/dataList/OA-15493](https://data.seoul.go.kr/dataList/OA-15493/A/1/datasetView.do)

### 기본 정보

| 항목 | 값 |
|---|---|
| **데이터셋 ID** | OA-15493 |
| **서비스명** | `bikeList` |
| **엔드포인트** | `http://openapi.seoul.go.kr:8088/{인증키}/{TYPE}/bikeList/{START}/{END}/` |
| **응답 포맷** | JSON / XML |
| **인증키** | 서울 열린데이터광장 일반 인증키 (자동 발급) |
| **라이선스** | 공공누리 1유형 (상업적 이용 허용) |
| **업데이트 주기** | 수시 (실측 1~5분) |

### 호출 제한

- **요청당 최대 1,000건**
- **전체 대여소 약 3,000+개** → 3~4회 분할 호출 필요
- **일일 트래픽 한도**: 기본 키 1,000건/일 (신청 시 확장 가능)
- 페이지네이션: URL 경로형 `START_INDEX/END_INDEX` (1-based, 양쪽 포함)

### 응답 필드 (rentBikeStatus.row[])

| 필드명 | 타입 | 설명 |
|---|---|---|
| `stationId` | String | 대여소 ID (예: `ST-10`) |
| `stationName` | String | 대여소 이름 (예: `102. 망원역 1번출구 앞`) |
| `stationLatitude` | String(Double) | 대여소 위도 |
| `stationLongitude` | String(Double) | 대여소 경도 |
| `rackTotCnt` | String(Int) | 거치대 총 개수 |
| `parkingBikeTotCnt` | String(Int) | 현재 거치 자전거 수 = 대여 가능 수량 |
| `shared` | String(Int) | 거치율(%) |

⚠️ 모든 숫자 필드가 **String**으로 반환됨. 클라이언트에서 캐스팅 필요.

### 상위 메타 필드

| 필드 | 설명 |
|---|---|
| `rentBikeStatus.list_total_count` | 전체 대여소 수 |
| `rentBikeStatus.RESULT.CODE` | 결과 코드 |
| `rentBikeStatus.RESULT.MESSAGE` | 결과 메시지 |

### 결과 코드

| CODE | 설명 |
|---|---|
| INFO-000 | 정상 처리 |
| INFO-100 | 인증키 유효하지 않음 |
| INFO-200 | 해당 데이터 없음 |
| ERROR-300 | 필수 값 누락 |
| ERROR-301 | 파일 형식 오류 |
| ERROR-500 | 서버 오류 |
| ERROR-600 | DB 연결 오류 |
| ERROR-601 | SQL 문장 오류 |

### 응답 예시

```json
{
  "rentBikeStatus": {
    "list_total_count": 3245,
    "RESULT": { "CODE": "INFO-000", "MESSAGE": "정상 처리되었습니다." },
    "row": [
      {
        "stationId": "ST-4",
        "stationName": "104. 합정역 1번출구 앞",
        "stationLatitude": "37.54956055",
        "stationLongitude": "126.91062927",
        "rackTotCnt": "15",
        "parkingBikeTotCnt": "8",
        "shared": "53"
      }
    ]
  }
}
```

### 호출 예시 (curl)

```bash
# JSON, 1~1000건
curl "http://openapi.seoul.go.kr:8088/{API_KEY}/json/bikeList/1/1000/"

# XML
curl "http://openapi.seoul.go.kr:8088/{API_KEY}/xml/bikeList/1/1000/"

# 전체 대여소 (분할 호출)
curl "http://openapi.seoul.go.kr:8088/{API_KEY}/json/bikeList/1/1000/"
curl "http://openapi.seoul.go.kr:8088/{API_KEY}/json/bikeList/1001/2000/"
curl "http://openapi.seoul.go.kr:8088/{API_KEY}/json/bikeList/2001/3000/"
curl "http://openapi.seoul.go.kr:8088/{API_KEY}/json/bikeList/3001/4000/"
```

---

## 3. 대여소 마스터/정적 정보

### OA-21235 (따릉이대여소 마스터 정보, TOPIS)
🔗 [data.seoul.go.kr/dataList/OA-21235](https://data.seoul.go.kr/dataList/OA-21235/S/1/datasetView.do?tab=A)
- 대여소 ID, 주소, 좌표 등 정적 메타정보 DB
- 출처: 서울시 교통정보 시스템(TOPIS)
- 갱신: 수시

### OA-13252 (대여소 정보)
🔗 [data.seoul.go.kr/dataList/OA-13252](https://data.seoul.go.kr/dataList/OA-13252/F/1/datasetView.do)
- 파일 다운로드 (CSV/XLSX), 반기 갱신
- 필드: 대여소명, 관리번호(stationId), 위치정보, 거치대 수, 자치구 등

### data.go.kr 15099365 (따릉이대여소 마스터 정보)
🔗 [data.go.kr/data/15099365](https://www.data.go.kr/data/15099365/fileData.do)
- 파일데이터, 동일 성격

---

## 4. 이력 / 통계 API

### OA-15182 / data.go.kr 15077786 (대여이력)
🔗 [OA-15182](https://data.seoul.go.kr/dataList/OA-15182/F/1/datasetView.do) / [data.go.kr 15077786](https://www.data.go.kr/data/15077786/openapi.do)
- 연도별 ZIP 파일 (2015~2025, 최대 2GB/년)
- 필드: 자전거번호, 대여일시, 대여 대여소번호/명, 반납일시, 반납 대여소번호/명, 이용시간(분), 이용거리(m)
- 대용량 → LTFviewer 등 별도 도구 필요

### OA-21229 (5분 단위 OD)
🔗 [data.seoul.go.kr/dataList/OA-21229](https://data.seoul.go.kr/dataList/OA-21229/F/1/datasetView.do)
- 출발 대여소 → 도착 대여소 5분 단위 승객수 (Origin-Destination)
- D-5 일자 데이터 로딩 (5일 지연)
- 필드: `대여소ID`, `시작_대여소명`, `종료_대여소명`, `승객수`, `집계_기준`

### OA-22382 (대여가능 수량 시간별)
🔗 [data.seoul.go.kr/dataList/OA-22382](https://data.seoul.go.kr/dataList/OA-22382/F/1/datasetView.do)
- 1시간 단위 대여소별 거치 수량 스냅샷 (배치 통계용)

### OA-14994 (이용현황)
🔗 [data.seoul.go.kr/dataList/OA-14994](https://data.seoul.go.kr/dataList/OA-14994/F/1/datasetView.do)
- 일별/시간별/월별/회원유형별/외국인별 집계 CSV

---

## 5. 따릉이 시스템 정보 (2026년 기준)

### 자전거 종류

| 구분 | 일반 따릉이 (LCD/QR) | 새싹 따릉이 |
|---|---|---|
| 바퀴 크기 | 24인치 | **20인치** |
| 무게 | 약 18kg | **약 16kg** |
| 이용 연령 | 만 15세 이상 | **만 13세 이상** |
| 권장 신장 | 160cm 이상 | **160cm 미만** 권장 |
| 자물쇠 | LCD / QR 단말기 | QR 단말기 |

⚠️ API 응답에서 두 종류가 동일 `stationId` 풀에 합쳐져 노출. **모델 구분 필드 미제공**.

### 요금 (2026년 기준)

**일일권**
- 1시간권: 1,000원
- 2시간권: 2,000원

**정기권 (1시간 기본 / 2시간 옵션)**

| 기간 | 1시간 | 2시간 |
|---|---|---|
| 7일권 | 3,000원 | 4,000원 |
| 30일권 | 5,000원 | 7,000원 |
| 180일권 | 15,000원 | — |
| 365일권 | 30,000원 | 40,000원 |

**연체료**: 기본 시간 초과 시 5분당 200원

### 운영 정보

| 항목 | 내용 |
|---|---|
| 운영 시간 | 24시간 무인 운영 |
| 대여소 수 | 약 3,000개+ (서울 25개 자치구) |
| 자전거 수 | 약 43,000대 (일반+새싹 합산) |
| 운영 주체 | 서울시설공단 / 서울특별시 교통실 |
| 공식 앱/웹 | bikeseoul.com, "서울자전거 따릉이" 앱 |
| 결제 | 카드결제, 간편결제(카카오/네이버페이), 티머니 |
| 문의 | 02-2133-2433 |

---

## 6. 모바일 앱 개발 실용 가이드

### 인증키 발급
- 서울 열린데이터광장에서 발급 (자동승인, 즉시 사용)
- ⚠️ 지하철 API 키와 **별도** (지하철은 1,000회/일 제한 있음, 따릉이는 일반키)

### 권장 호출 패턴

**1. 정적 데이터 (대여소 마스터)**
- OA-13252 또는 OA-21235로 대여소 정보를 앱 번들/캐시에 저장
- 초기 1회 다운로드 후 주기적 갱신 (월 1회 등)

**2. 동적 데이터 (실시간 잔여)**
- OA-15493 `bikeList`를 1~5분 폴링
- 변경되는 필드: `parkingBikeTotCnt`, `shared` 만

### 호출 최적화
- 1,000건 제한 → 최소 4회 호출 + **병렬 처리**
- 화면 표시 영역만 필터링하여 메모리 절감
- 마지막 호출 결과 캐시 → 네트워크 실패 시 재사용

### 타입 변환 주의
- 모든 숫자 필드가 String → Int/Double 캐스팅 필요
- 위/경도는 WGS84 → MapKit/네이버지도 직접 사용 가능

### UX 고려 사항

| 상황 | `parkingBikeTotCnt` | `shared` | UI 처리 |
|---|---|---|---|
| 대여 불가 | 0 | 0% | 회색 배경, "대여 불가" |
| 여유 | 1~50% | 30~70% | 녹색 |
| 부족 | >70% | >70% | 주황 |
| 반납 불가 | rackTotCnt와 동일 | 100% | 빨강, "반납 불가" |

### 한계

- **자전거 종류 구분 불가**: 새싹/일반 따릉이는 API로 구분 안 됨
- **GBFS 미지원**: 따릉이는 글로벌 표준 GBFS를 공식 제공하지 않음
- **이력/통계 데이터**: 실시간 API에는 포함 안 됨 → 분석용은 별도 파일 처리
- **노선/경로 API 없음**: 자전거 도로 정보는 별도 제공 안 됨

---

## 7. 관련 링크

### 서울 열린데이터광장
- [OA-15493 실시간 대여정보](https://data.seoul.go.kr/dataList/OA-15493/A/1/datasetView.do)
- [OA-13252 대여소 정보](https://data.seoul.go.kr/dataList/OA-13252/F/1/datasetView.do)
- [OA-21235 대여소 마스터(TOPIS)](https://data.seoul.go.kr/dataList/OA-21235/S/1/datasetView.do?tab=A)
- [OA-15182 대여이력](https://data.seoul.go.kr/dataList/OA-15182/F/1/datasetView.do)
- [OA-14994 이용현황](https://data.seoul.go.kr/dataList/OA-14994/F/1/datasetView.do)
- [OA-21229 대여/반납 OD](https://data.seoul.go.kr/dataList/OA-21229/F/1/datasetView.do)
- [OA-22382 대여가능 수량](https://data.seoul.go.kr/dataList/OA-22382/F/1/datasetView.do)

### 공공데이터포털
- [공공자전거 OpenAPI 묶음](https://www.data.go.kr/dataset/3045310/openapi.do)
- [공공자전거 대여이력](https://www.data.go.kr/data/15077786/openapi.do)

### 기타
- [서울교통 빅데이터 - 따릉이 운영 대여소](https://t-data.seoul.go.kr/category/dataviewopenapi.do?data_id=1044)
- [따릉이 공식 - 이용요금](https://www.bikeseoul.com/info/infoCoupon.do)
- [따릉이 공식 - 이용안내](https://www.bikeseoul.com/info/infoReg.do)
- [서울시 따릉이 소개](https://news.seoul.go.kr/traffic/archives/33719)
