# Phase 0 Research: 핀 기반 동네 인사이트

대부분의 데이터·기술 불확실성은 사전 검증(2026-06-19, `Documents/Work/260619_1_pin_insight/requirements.md` + API 검증)에서 해소됨. 핵심 결정만 정리.

## D1. 점(좌표) → 행정동/자치구 매핑
- **Decision**: Kakao Local `coord2regioncode` API 사용(무료 10만/일).
- **Rationale**: 앱이 이미 Kakao를 사용. 행정동 경계 GeoJSON을 앱에서 일괄 보유할 필요 없이 좌표→행정동/자치구 코드를 즉시 얻음(가벼움).
- **Alternatives**: 행정동 경계 GeoJSON 내장 후 point-in-polygon → 데이터·전처리 부담으로 기각.

## D2. 좌표계 변환
- **Decision**: 서울 데이터의 TM(EPSG:5174)·GRS80/UTM-K(EPSG:5179) 좌표를 WGS84로 변환하는 유틸(`CoordinateTransform`) 제공.
- **Rationale**: 약국·버스정류소 등 일부 데이터셋이 TM 좌표. 지도(WGS84)와 반경 계산을 위해 통일 필요.
- **Alternatives**: WGS84 제공 데이터셋만 사용 → 카드 커버리지 축소로 기각. 변환은 표준 공식으로 경량 구현.

## D3. 카드별 데이터 소스 (검증 완료)
| 카드 | 데이터셋 | 단위/질의 | 비고 |
|---|---|---|---|
| 생활 활기 | 행정동 생활인구 OA-14991 | 행정동(좌표X) | coord2regioncode 매칭 |
| 대기질 | RealtimeCityAir OA-1200 | 자치구 | 실시간, 기준시각 표시 |
| 교통-따릉이 | 따릉이 OA-15493 | 반경(좌표) | 실시간 잔여, 기준시각 |
| 교통-지하철 | 역사좌표 OA-22534 | 최근접(위경도) | CSV 정적, 변환 불필요 |
| 교통-버스 | OA-15067/OA-1094 | 최근접 | TM 변환 가능성 |
| 편의 | 약국(NMC 15000576)·화장실(파일)·와이파이 OA-20883 | 반경 | 일부 파일 선적재 |
| 녹지 | 도시공원 표준 15012890 | 최근접 | 둘레길(OA-11986)=4유형 제외 |
| 안전 | 안심이CCTV OA-20923·보안등·침수 OA-15636·범죄 OA-13532 | 반경/면/자치구 | 방범CCTV OA-21097=4유형 제외 |
| 지금 | 문화행사 OA-15486 | 반경+기간 | 위경도+일정 |

- **제외**: 소음(S-DoT OA-15969 좌표 비공개), 둘레길·방범CCTV(공공누리 4유형 상업금지).

## D4. 카드별 반경 (Clarify 결정: 카드 종류별로 다르게)
- **Decision**: 반경을 카드 종류별로 차등.
  - 화장실/와이파이: ~300m
  - 약국/병원·따릉이·문화행사: ~500m
  - 공원·지하철역(최근접): 반경 없음(최근접 1개) 또는 ~1km
- **Rationale**: 도보 실수요 빈도·시설 밀도에 맞춤. 화장실은 가까워야 의미, 공원은 넓게.
- **세부 값**: data-model의 카드 정의에 상수로 둠(추후 조정 가능).

## D5. 실시간 값 신선도 (Clarify 결정)
- **Decision**: 실시간 카드(따릉이·대기질)에 데이터 기준 시각을 '○분 전'으로 표시.
- **Rationale**: 실시간 값의 신뢰도·맥락 제공. staleness 경고 대신 사실 표기.

## D6. 관심 동네 저장 (Clarify 결정)
- **Decision**: 저장은 위치 북마크. 다시 열면 최신 데이터로 재조회(스냅샷 미보존).
- **Rationale**: 실시간 값이 의미 있는 도메인. 스냅샷 보존은 복잡도만 증가(YAGNI).
- **Storage**: SwiftData(좌표·행정동명·저장시각만).

## D7. 병렬 집계 & 부분 실패 격리
- **Decision**: `NeighborhoodInsightService`가 카드별 fetch를 `async let`/`TaskGroup`으로 병렬 실행, 각 카드는 독립 결과(성공/실패/로딩). `InsightViewModel`이 `CurrentValueSubject`로 카드별 상태 스트림.
- **Rationale**: 첫 카드 <1.5s·전체 <3s 목표, 한 API 실패가 전체를 막지 않음(FR-010).

## D8. 캐싱 전략
- **Decision**: 실시간(대기질·따릉이) 분 단위 메모리 캐시 / 준정적(시설·역좌표) 일 단위 / 정적(화장실 CSV) 앱 번들+Documents 캐시.
- **Rationale**: 호출 절감 + 일부 오프라인 동작 + rate limit 대응.

## D9. 표시 = 기존 POI 팝업 재사용
- **Decision**: `PinInsightContent: MapItemContent`로 `MapItemDetailViewController` 재사용. 헤더(`DrawerHeaderView`)+카드 스크롤+푸터(`FooterAction`: 경로/저장/공유).
- **Rationale**: 신규 화면 0개, 따릉이·버스 상세와 동일 UX(학습 부담 0), 002 디자인 토큰 자동 정합.

## 미해결(개발 중 실데이터로 확인 — 비차단)
- 버스(OA-15067/1094) 좌표 컬럼이 경위도인지 TM인지 실측.
- 약국/병원 API 응답 좌표 필드 verbatim.
- 침수흔적도 파일 EPSG·포맷(선적재 시 확인).
</content>
