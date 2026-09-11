# Phase 1 Data Model: 핀 기반 동네 인사이트

## NeighborhoodInsight (집계 결과)
한 핀 좌표에 대한 종합 결과(메모리 모델, 비영속).

| 필드 | 타입 | 설명 |
|---|---|---|
| coordinate | `CLLocationCoordinate2D` | 핀 좌표(WGS84) |
| regionCode | `RegionCode` | 행정동/자치구 코드·명(coord2regioncode 결과) |
| summary | `String` | 한 줄 요약(규칙 기반 생성) |
| cards | `[InsightCard]` | 카드 묶음(고정 순서) |

- 검증: 서울 영역 밖이면 생성하지 않고 안내(FR-014).

## RegionCode
| 필드 | 타입 | 설명 |
|---|---|---|
| guName | `String` | 자치구명 |
| dongName | `String` | 행정동명 |
| guCode / dongCode | `String` | 코드(문자열, 앞자리 0 보존) |

## InsightCard (카드)
카드 = 한 지표의 표시 단위. enum kind + 상태.

| 필드 | 타입 | 설명 |
|---|---|---|
| kind | `InsightCardKind` | vitality/airQuality/transit/amenity/greenery/safety/events |
| state | `CardState` | `.loading` / `.loaded(CardValue)` / `.failed` |
| asOf | `Date?` | 실시간 카드의 데이터 기준 시각(없으면 nil) → '○분 전' 표시 |

- `CardState`: 카드별 독립(FR-010). 실패는 "정보 없음"으로 표시, 전체 비차단.
- `CardValue`: 카드 종류별 표시 데이터(등급/수치/목록).

### 카드별 값(요약)
| kind | 핵심 값 | 단위/반경 | 실시간 |
|---|---|---|---|
| vitality | 활기 등급(붐빔/보통/한적) + 시간대 추이 | 행정동 | — |
| airQuality | 통합대기환경지수 등급 | 자치구 | ✅ asOf |
| transit | 최근접 지하철 도보분 / 버스 / 따릉이 잔여 | 최근접·반경500m | 따릉이 ✅ asOf |
| amenity | 병원·약국·화장실·와이파이 개수+최근접 | 화장실·와이파이 300m / 약국 500m | — |
| greenery | 최근접 공원 | ~1km/최근접 | — |
| safety | 야간시설 밀도·자치구 범죄수준·침수이력 | 반경/자치구/점-폴리곤 | — |
| events | 주변 행사 목록 | 반경500m+기간 | — |

## SavedNeighborhood (SwiftData, 영속)
| 필드 | 타입 | 설명 |
|---|---|---|
| id | `UUID` | 식별자 |
| latitude / longitude | `Double` | 저장 위치 |
| dongName | `String` | 표시용 동네명 |
| savedAt | `Date` | 저장 시각 |

- **재방문 시 최신 재조회**(스냅샷 미보존, D6). 저장은 위치 북마크 성격.
- 기존 SwiftData 스토어 구성에 신규 모델/스토어로 추가.

## 관계
- `NeighborhoodInsight 1 — N InsightCard`
- `SavedNeighborhood`는 좌표만 보존 → 열람 시 `NeighborhoodInsightService`로 `NeighborhoodInsight` 재생성.
</content>
