---
description: "Task list for 실시간 도시 혼잡 지도 (Live City Pulse)"
---

# Tasks: 실시간 도시 혼잡 지도 (Live City Pulse)

**Input**: Design documents from `/specs/004-live-congestion/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/live-pulse-ui.md, quickstart.md

**Tests**: 혼잡 단계 파싱·offset 선택·가시영역 필터 등 순수 로직은 Swift Testing(spec S7). 데이터·UI는 시뮬레이터 로그 검증.

**Base path**: 소스 경로는 `Navigation/Navigation/` 하위, 테스트는 `Navigation/NavigationTests/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일·의존 없음 → 병렬 가능
- **[Story]**: US1/US2/US3 (Setup·Foundational·Polish는 라벨 없음)

---

## Phase 1: Setup

**Purpose**: baseline + 정적 카탈로그 확보

- [X] T001 시뮬레이터 `iPhone 17 Pro`로 현재 main baseline 빌드 확인 (`xcodebuild -project Navigation/Navigation.xcodeproj -scheme Navigation -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`)
- [X] T002 서울 실시간도시데이터 ~120 핫스팟 (장소명→좌표) 목록 수집해 `Navigation/Navigation/Resources/hotspots.json` 번들 추가 (소량 정적, research R2)

---

## Phase 2: Foundational — 데이터 백본 (모든 US 선행)

**Purpose**: citydata_ppltn 호출·디코딩·혼잡단계·캐시. US1~US3 공통 전제.

**⚠️ 완료 전 US 단계 진행 불가** (혼잡 데이터 없이는 마커·슬라이더·상세 모두 불가)

- [X] T003 [P] `Service/LivePulse/CitydataModels.swift` — `citydata_ppltn` 응답 디코딩(`AREA_NM`·`AREA_CONGEST_LVL`·`AREA_PPLTN_MIN/MAX`·`PPLTN_TIME`·`FCST_PPLTN[]`{`FCST_TIME`·`FCST_CONGEST_LVL`·`FCST_PPLTN_MIN/MAX`}). 필드명은 첫 호출 로그로 확정(research R1)
- [X] T004 [P] `Feature/LivePulse/CongestionLevel.swift` — 4단계 enum(붐빔/약간붐빔/보통/여유)+`unknown`, `init(rawText:)` 파싱(공백·표기 변형 허용), `color(for:)`(Theme.Palette, WCAG). 순수 함수
- [X] T005 [P] `Service/LivePulse/HotspotCatalog.swift` — 번들 `hotspots.json` 로드(장소명→좌표), `visibleAreas(in rect:) -> [String]`(가시 영역 ∩ 카탈로그)
- [X] T006 `Service/LivePulse/CitydataService.swift` — `SeoulAPIClient`로 `citydata_ppltn` **장소별 병렬 호출**(타임아웃·부분실패 허용 → 받은 것만), `areaName` 키 **TTL 캐시(5분)**, 응답+카탈로그 좌표 병합 → `CongestionPlace`. (T003·T005 의존)
- [X] T007 [P] `NavigationTests/CongestionLevelTests.swift` — 단계 파싱(4단계+변형+결측→unknown) 단위 테스트

**Checkpoint**: 카탈로그·서비스·단계 파싱 동작(로그로 표본 장소 혼잡/예측 확인), 단위 테스트 통과.

---

## Phase 3: User Story 1 — 지금 어디가 붐비나 (실시간 마커 레이어) (Priority: P1) 🎯 MVP

**Goal**: 보이는 영역 핫스팟을 혼잡 단계색 마커로 표시 + 기준 시각 + 진입/종료 복원.

**Independent Test**: 혼잡 버튼 진입 → 가시 영역 마커 단계색 + 기준시각, 카메라 이동 시 추가 로딩, 종료 시 복원.

- [X] T008 [US1] `Map/Congestion/CongestionAnnotation.swift` + `CongestionAnnotationView.swift` — 단계색 마커(bike/bus 어노테이션 패턴)
- [X] T009 [US1] `Map/MapViewController.swift` — `setCongestion(places:)`/`clearCongestion()`/마커 추가·제거, 표준 지도 고정·카메라 유지. 기존 `rendererFor`/오버레이 영향 없음
- [ ] T010 [US1] `Map/MapViewController.swift` — `onRegionChanged`(L460) 구독으로 **가시 영역 로딩 콜백**(`onCongestionRegionNeedsLoad(rect)`) 노출 (T009와 동일 파일 → 순차)
- [ ] T011 [US1] `Feature/LivePulse/LivePulseViewModel.swift` — `CurrentValueSubject` `places`·`isRefreshing`, `loadVisible(rect:)`(CitydataService 호출 누적·병합), `refresh()`. 부분/전체 실패 상태 노출
- [ ] T012 [US1] `Feature/LivePulse/LivePulseDrawerViewController.swift` — 기준 시각 라벨(FR-003) + 새로고침 버튼 + 닫기. (시간 슬라이더는 US2)
- [X] T013 [P] [US1] `Feature/Home/MapControlButtonsView.swift` — `onLivePulseTapped` 콜백 + 전용 버튼(맥박/혼잡 아이콘)
- [X] T014 [US1] `Coordinator/AppCoordinator.swift` + `Feature/Home/HomeViewController.swift` — `showLivePulse()`/`exitLivePulse()`: 따릉이·버스 레이어 저장→OFF·복원(토글 값 보존), 위성→표준, 카메라 유지, `pushDrawer`/`popDrawer`, 가시영역 로딩 배선
- [ ] T015 [US1] 부분실패/오프라인 처리(FR-011/012) — 받은 장소만 표시·빈 곳 미표시, 전체 실패/오프라인 시 마지막 캐시+기준시각+상태 안내

**Checkpoint**: 진입 시 가시 영역 혼잡 마커+기준시각, 이동 시 추가 로딩(캐시 적중), 종료 복원. 일부 실패에도 받은 것 표시.

---

## Phase 4: User Story 2 — 가까운 미래로 돌려보기 (예측 슬라이더) (Priority: P2)

**Goal**: 지금→+N시간 슬라이더로 각 마커 색을 예측 단계로 갱신.

**Independent Test**: 슬라이더 +N → 마커 색 예측으로 갱신(네트워크 없이), "지금" 복귀 시 실시간.

- [X] T016 [US2] `Feature/LivePulse/LivePulseViewModel.swift` — `TimelineState.offsetHour` + `setOffset(_:)`, `markerLevel(place:offset:)`(0=live, N=forecast[N-1]), `maxOffset`(가시 장소 예측 길이 안전 최소). (T011과 동일 파일 → 순차)
- [X] T017 [US2] `Feature/LivePulse/LivePulseDrawerViewController.swift` — 시간 슬라이더(0~maxOffset) 추가, offset→ViewModel. (T012와 동일 파일 → 순차)
- [X] T018 [US2] `Map/MapViewController.swift` — `updateCongestionColors(provider:)` 슬라이더 변경 시 마커 색 갱신(재요청 없음). (T009와 동일 파일 → 순차)
- [X] T019 [P] [US2] `NavigationTests/CongestionLevelTests.swift` — offset→level 선택(0=live, N=forecast[N-1]), 예측 부족 시 중립, maxOffset clamp 단위 테스트

**Checkpoint**: 슬라이더로 예측 스크럽 0.3초 내 색 갱신, 예측 부족 장소 중립, 지금 복귀.

---

## Phase 5: User Story 3 — 장소 상세 예측 곡선 (Priority: P3)

**Goal**: 마커 탭 → 실시간 혼잡 + 예측 곡선 + 기준 시각.

**Independent Test**: 마커 탭 → 그 장소 실시간/예측 곡선 표시.

- [X] T020 [US3] `Feature/LivePulse/CongestionContent.swift` — `MapItemContent` 구현(실시간 단계·인구 + 예측 곡선(SwiftUI 미니차트) + 기준시각)
- [X] T021 [US3] `Coordinator/AppCoordinator.swift` + `Map/MapViewController.swift` — 혼잡 마커 탭 → `showMapItemDetail(content: CongestionContent)`(핀 인사이트 팝업 재사용)

**Checkpoint**: 마커 탭 시 실시간+예측 곡선·기준시각 표시.

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: 신선도·디자인·회귀

- [ ] T022 [P] 혼잡 색 디자인 토큰 점검 — 4단계 색이 `Theme.Palette` 경유·색각/명도 WCAG(FR-013), 시스템색 하드코딩 없음
- [ ] T023 [P] 신선도 마감(FR-007) — TTL 5분(원천 주기) 설정 + 만료 시 재요청, 기준 시각 라벨 일관 표시. (자동 타이머 갱신은 Later — 이번 미포함)
- [X] T024 회귀 검증 — 혼잡 모드 진입/종료가 기존 홈(따릉이·버스 레이어·검색·핀 인사이트·지도) 동작에 영향 없음. 개발용 print 로그 정리
- [X] T025 [P] 호출량 로그 확인 — 가시 영역당 호출 수·캐시 적중률 로그로 과다 호출 없음 확인(FR-007a)

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2(데이터 백본)**: 반드시 선행. T006은 T003·T005 의존.
- **US1(P3)·US2(P4)·US3(P5)**: Foundational 완료 후. US2는 US1의 마커/뷰모델 위에 슬라이더를 얹음(같은 파일 순차). US3는 마커 탭만 사용 → US1 후 독립.
- **Polish(Phase 6)**: 모든 US 후.

### Story별 독립성
- **US1**: 실시간 마커 레이어 — Foundational만 있으면 단독 데모(P1 MVP, offset 고정 0).
- **US2**: 예측 슬라이더 — US1 마커 위 offset 추가.
- **US3**: 장소 상세 — 마커 탭 팝업, 다른 스토리와 약결합.

## Parallel Opportunities

- **Foundational**: T003·T004·T005·T007 [P] 병렬(다른 파일). T006은 T003·T005 후.
- **US1**: T013 [P] 병렬. T008→T009→T010(맵), T011→T012 흐름 순차.
- **US2**: T019 [P] 테스트 병렬. T016→T017→T018 순차.
- **Polish**: T022·T025 [P].

## Implementation Strategy

1. **MVP = Phase 1+2+US1**: 보이는 영역 실시간 혼잡 마커(offset 0) + 기준시각 + 복원. 핵심 가치 완성.
2. **+US2**: 지금→예측 슬라이더.
3. **+US3**: 장소 상세 곡선.
4. **Polish**: 색 토큰·갱신주기·회귀·호출량.

**총 25 태스크** — Setup 2 / Foundational 5 / US1 8 / US2 4 / US3 2 / Polish 4.
