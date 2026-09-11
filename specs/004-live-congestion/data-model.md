# Phase 1 Data Model: 실시간 도시 혼잡 지도 (Live City Pulse)

영속 SwiftData 엔티티 없음. 라이브 응답 모델 + 번들 정적 매핑 + 런타임 상태/파생값.

## 1. CongestionPlace (런타임, 라이브 + 정적 병합)

한 핫스팟의 표시 단위. `citydata_ppltn` 응답 + 번들 좌표 매핑(R2) 병합.

| 필드 | 출처 | 설명 |
|---|---|---|
| areaName | 번들/응답 `AREA_NM` | 장소명(호출 키이자 표시명) |
| coordinate | **번들 매핑(R2)** | 마커 좌표(응답에 없을 가능성) |
| liveLevel | `AREA_CONGEST_LVL` | 실시간 혼잡 단계(붐빔/약간붐빔/보통/여유) |
| livePopulation | `AREA_PPLTN_MIN/MAX` | 실시간 인구 범위(상세용) |
| baseTime | `PPLTN_TIME` | 기준 시각(신선도, FR-003) |
| forecast | `FCST_PPLTN[]` | 예측 시계열(아래) |

**검증**: 좌표 없으면 마커 못 찍음 → 번들 매핑에 없는 장소는 제외(FR-011). liveLevel 결측 → 표시 안 함.

## 2. CongestionForecast (예측 1점)

| 필드 | 출처 | 설명 |
|---|---|---|
| time | `FCST_TIME` | 예측 시각 |
| level | `FCST_CONGEST_LVL` | 예측 혼잡 단계 |
| populationRange | `FCST_PPLTN_MIN/MAX` | 예측 인구(곡선용) |

**규칙**: 배열 길이 = 예측 개수(~12, 실데이터 확정). 슬라이더 최대 offset = min(12, 길이). 부족 장소는 그 offset에서 중립.

## 3. CongestionLevel (열거)

`붐빔 > 약간 붐빔 > 보통 > 여유` 4단계 + `unknown`(결측/커버리지 밖 → 표시 안 함/중립). 단계→색은 `Theme.Palette`(WCAG, FR-013).

## 4. HotspotCatalog (번들 정적, R2)

(장소명 → 좌표) 매핑 ~120개. 작은 JSON, 번들 동봉. 호출 대상 목록이자 좌표 출처. 갱신 드묾(앱 업데이트).

## 5. TimelineState (런타임)

`LivePulseViewModel`의 `CurrentValueSubject<TimelineState, Never>`.

| 필드 | 타입 | 설명 |
|---|---|---|
| offsetHour | Int (0~N) | 0=지금(실시간), N=+N시간(예측) |
| isRefreshing | Bool | 갱신 중 |

**전이**: 슬라이더 → offset 변경 → 각 장소 표시 단계 재선택(실시간↔예측), 네트워크 없이 즉시(이미 받은 예측). 카메라 이동 → 새 영역 로딩(R3). TTL 만료/수동 → 재요청.

## 6. 파생값 (저장 안 함)

- **마커 색**: 각 CongestionPlace의 현재 offset 단계 → 색. offset 0=liveLevel, N=forecast[N-1].level.
- **장소 곡선(US3)**: forecast 배열 → 단계/인구 곡선.
- **가시 장소 집합**: visibleMapRect ∩ HotspotCatalog → 로딩 대상(R3).

## 7. 캐시 (런타임, 비영속)

장소별 `citydata_ppltn` 응답 **TTL 캐시**(예: 5분). 키=areaName. 핀 인사이트 정적 TTL 캐시 패턴 재사용. 만료 시 재요청, 오프라인 시 만료값+기준시각 표시.
