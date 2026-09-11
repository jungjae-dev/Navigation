# Phase 0 Research: 실시간 도시 혼잡 지도 (Live City Pulse)

브리프(Documents/Work/260622_live_congestion) + 코드 스캔(2026-06-22, 브랜치 004) 기준. clarify 결정과 데이터/렌더링 선택을 정리한다.

## R1. 데이터 소스 — 서울 실시간 도시데이터 (citydata_ppltn)

**Decision**: 경량 인구/혼잡 엔드포인트 **`citydata_ppltn`** 사용(전체 `citydata`는 도로·주차 등 불필요 필드 과다). 기존 `SeoulAPIClient`로 호출(동일 호스트 `openapi.seoul.go.kr:8088`, 키 path, json).

**응답 핵심 필드(예상, 실데이터 1회 확정)**:
- `AREA_NM`(장소명), `AREA_CONGEST_LVL`(혼잡단계: 붐빔/약간 붐빔/보통/여유), `AREA_PPLTN_MIN/MAX`(실시간 인구), `PPLTN_TIME`(기준 시각).
- `FCST_PPLTN`(예측 배열): 각 `FCST_TIME`, `FCST_CONGEST_LVL`, `FCST_PPLTN_MIN/MAX`. **~12개(시간 단위, 약 +12h) 예상** → 슬라이더 0~12 매핑.

**호출 구조**: **장소(AREA_NM)별 1회 호출** → 전체 ~120곳을 다 부르면 무거움(FR-007a 뷰포트 로딩으로 해결, R3).

**근거**: 혼잡 단계·예측을 서울시가 직접 제공 → 앱은 디코딩·표시만(자체 모델 없음, FR-005). 핀 인사이트의 서울 OpenAPI 디코딩·TTL 캐시 패턴 재사용.

**Open spike(실데이터 1회)**: `FCST_PPLTN` 개수·간격·시간범위, 필드명 verbatim, 응답에 좌표 포함 여부(R2).

## R2. 장소 좌표 — 번들 매핑 테이블 (소량)

**Decision**: `citydata_ppltn`은 장소명 기반이라 응답에 좌표가 없을 가능성 큼 → **공식 ~120 핫스팟의 (장소명 → 좌표) 매핑을 앱 번들에 동봉**(작은 정적 JSON).

**근거**: 마커를 찍으려면 좌표 필수. 핫스팟 목록은 고정·공개(서울 실시간도시데이터 POI 목록). 소량(수 KB)이라 번들 적합. 호출도 이 목록으로 "장소명"을 만든다.

**검증**: 공식 POI 목록과 좌표 1회 수집 → 번들. 목록 갱신은 드물어 앱 업데이트로 충분.

## R3. 뷰포트 우선 로딩 (FR-007a, clarify Q1)

**Decision**: 진입/카메라 이동 시 **보이는 지도 영역(visibleMapRect) 안의 핫스팟만** 골라 `citydata_ppltn` 병렬 호출. 결과는 **장소별 TTL 캐시**(예: 5분)로 재요청 최소화. 타임아웃·부분 실패 허용.

**근거 (실제 코드)**: `MapViewController.onRegionChanged`(L460) + `regionDidChangeAnimated`(L868)가 이미 영역 변경 콜백 제공. `updateBus/BikeAnnotationsVisibility`(L549/629)가 영역 기반 표시 패턴의 선례. 보이는 영역 핫스팟은 보통 <20곳 → 호출량·지연 급감(SC-002).

**부분 실패(FR-012)**: 병렬 호출 중 실패 장소는 스킵(받은 것만 표시), 전체 실패 시 상태 안내. 서울 API 다운 이력 대비 타임아웃 필수(핀 인사이트서 10s 적용 선례).

**Alternatives**: 전체 일괄(B)·상위 N(C) — clarify에서 기각.

## R4. 표시 — 혼잡 단계색 마커 (FR-002, clarify Q2)

**Decision**: 각 핫스팟 좌표에 **혼잡 단계색 마커**(커스텀 `MKAnnotationView`). 슬라이더 offset 변경 시 마커 색만 그 시각 예측 단계로 갱신.

**근거 (실제 코드)**: bike/bus 어노테이션(`BikeAnnotation`/`setBusStops`/visibility) 패턴 재사용. 데이터가 POI 단위라 마커가 자연스럽고 좌표만으로 구현(면은 경계 필요 → Later).

**색 매핑**: 4단계(붐빔/약간붐빔/보통/여유) → `Theme.Palette` 순차색, 색각·명도 WCAG(FR-013). 결측/커버리지 밖 = 표시 안 함(FR-011).

## R5. 시간 슬라이더 (FR-004) — offset→예측 선택

**Decision**: 슬라이더 = **offset 0~예측개수**. offset 0 → `AREA_CONGEST_LVL`(실시간), offset N → 그 장소 `FCST_PPLTN[N-1]`의 `FCST_CONGEST_LVL`. 슬라이더 최대는 응답 예측 개수에 맞춤(부족 장소는 그 시각 중립, FR-004 Edge).

**상태**: `LivePulseViewModel`의 `CurrentValueSubject<TimelineState>`(offset, refresh). 이미 받은 예측 기준이라 offset 변경은 네트워크 없이 즉시 색 갱신(SC-002). 자동 재생(타임랩스)은 Later.

## R6. 장소 상세 곡선 (FR-006) — 상세 팝업 재사용

**Decision**: 마커 탭 → `AppCoordinator.showMapItemDetail(content:)`에 **`CongestionContent: MapItemContent`** 전달(실시간 혼잡 + 예측 곡선 + 기준 시각). 핀 인사이트 팝업 인프라 그대로.

**근거 (실제 코드)**: `showMapItemDetail(content: any MapItemContent)`(L510), `showNeighborhoodInsight`(L446) 선례. 곡선은 SwiftUI 미니 차트.

## R7. 진입/종료·레이어 배타 (FR-008/009/010)

**Decision**: `DrawerContainerManager.pushDrawer`로 시간 드로어 ON(홈 드로어 내려감), 종료 시 `popDrawer`. 진입 시 따릉이·버스 레이어 on/off 저장→OFF, 표준 지도 고정, 카메라 유지; 종료 시 복원(토글 값 보존). 진입점 = `MapControlButtonsView` 전용 버튼 + `AppCoordinator.showLivePulse()/exitLivePulse()`.

**근거**: 시간여행에서 설계한 동일 패턴. `MapControlButtonsView` 콜백 패턴, `pushDrawer/popDrawer` 확인.

## R8. 신선도/갱신 (FR-003/007)

**Decision**: 표시값에 **기준 시각(`PPLTN_TIME`)** 항상 노출. 자동 갱신 주기 + 수동 새로고침. TTL(예: 5분) 만료 시 재요청. 오프라인이면 마지막 캐시 + 기준 시각 + 새로고침 유도.

**갱신 주기(디자인 결정, Deferred)**: 5분 기본 제안, 구현 시 확정.

## R9. 비목표 / Later
- 면(영역) 색칠, 자동 타임랩스 재생/속도, 대기질·따릉이 흐름 결합, 도보 경로 "혼잡 회피" 연계, 핀 인사이트 시간곡선 통합 — Later.

## 미해결 → 구현 스파이크/디자인
- `citydata_ppltn` 예측 개수·간격·필드명, 좌표 포함 여부 — 구현 첫 호출 시 확정(R1/R2).
- 혼잡 색 팔레트·갱신 주기 — 디자인(R4/R8).
