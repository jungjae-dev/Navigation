---
description: "Task list for 사용자 화면 디자인·레이아웃 통일 리팩토링"
---

# Tasks: 사용자 화면 디자인·레이아웃 통일 리팩토링

**Input**: Design documents from `/specs/002-ui-design-refresh/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: 본 작업은 시각·레이아웃 리팩토링이며 스펙에서 TDD를 요구하지 않음 → 테스트 태스크는 선택(Polish에서 경량 회귀 테스트만 옵션 제공). 완료 판정은 시뮬레이터 시각 검증(quickstart.md).

**Organization**: 토큰/공통 컴포넌트(Foundational)를 먼저 단일 기준화한 뒤, 사용자 스토리별로 화면을 정렬한다.

**경로 베이스**: 모든 소스 경로는 `Navigation/Navigation/` 기준. (예: `Common/UI/Theme.swift` = `Navigation/Navigation/Common/UI/Theme.swift`)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 다른 파일·의존성 없음 → 병렬 가능
- **[Story]**: US1/US2/US3 (Setup·Foundational·Polish는 라벨 없음)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 토큰 작업 전 베이스라인 및 자산 준비

- [X] T001 인디고 액센트 색상 세트 추가: `Assets.xcassets/AccentIndigo.colorset/Contents.json` (Any Appearance #4F46E5, Dark #818CF8) 생성 (research D1)
- [X] T002 [P] 토큰 미준수 베이스라인 감사: 인스코프 화면 대상 하드코딩 색(`UIColor(`, `.blue`, `systemGray`)·인라인 폰트(`UIFont.systemFont(ofSize:`)·매직 곡률(14/24)을 grep로 수집해 `specs/002-ui-design-refresh/contracts/screen-inventory.md` 체크 항목에 현황 주석으로 기록

**Checkpoint**: 자산·감사 베이스라인 준비 완료

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 모든 화면이 상속하는 단일 토큰·디테 프리셋·공통 컴포넌트 기반. 이 단계 완료 전 어떤 스토리도 시작 불가.

**⚠️ CRITICAL**: 모든 사용자 스토리는 이 단계 완료에 의존

- [X] T003 `Common/UI/Theme.swift`의 `Theme.Colors`에 `accent`(에셋 `AccentIndigo` 기반) 및 필요 시 `accentSubtle` 추가 (data-model §1.1, research D1)
- [X] T004 `Common/UI/Theme.swift`의 `Theme.Fonts` 본문 계열(largeTitle/title/headline/body/callout/subheadline/footnote/caption)을 `UIFontMetrics(forTextStyle:).scaledFont(for:)` 기반 스케일 폰트로 전환. 주행 전용 폰트(maneuverDistance/maneuverInstruction/eta)는 고정 유지 (data-model §1.2, research D2)
- [X] T005 [P] `Common/UI/DrawerDetent.swift`에 표준 detent 프리셋 `.peek`/`.half`/`.full` 정의 추가 (data-model §2, research D4)
- [X] T006 [P] `Common/UI/DesignSystem/EmptyStateView.swift` 신규 생성 — empty/loading 변형, 토큰(IconSize.xxxl·중립 tint·headline·footnote) 사용 (data-model §3, contracts C8)
- [X] T007 `Common/UI/DesignSystem/Theme+Component.swift`: `Card.backgroundOpacity`를 1.0(불투명 솔리드)로 정렬하고, `Button.Primary/Secondary`의 강조색을 `Theme.Colors.accent`로 라우팅 (research D3, data-model §4)
- [X] T008 [P] `Common/UI/DesignSystem/Theme+Drawer.swift`: `Cell.iconColor`·`SectionHeader.iconColor` 등 강조 지점을 accent 절제 규칙에 맞게 정리(장식은 중립색), 고정 height를 "최소 height" 의미로 사용하도록 주석/상수 정비 (data-model §4, contracts C4)

**Checkpoint**: 토큰·프리셋·EmptyStateView 준비 완료 — 공통 컴포넌트 및 화면 작업 시작 가능

---

## Phase 3: User Story 1 - 모든 화면이 하나의 앱처럼 통일된 인상 (Priority: P1) 🎯 MVP

**Goal**: 공유 디자인 시스템 컴포넌트 전체가 단일 토큰(색/서체/간격/곡률/상태)을 따르게 하여, 이들을 쓰는 모든 화면이 즉시 통일된 인상을 갖게 한다.

**Independent Test**: 공통 컴포넌트를 사용하는 화면들을 캡처해 나란히 비교 시 강조색·타이포 계층·여백·곡률·버튼 스타일이 동일 규칙을 따르고, 라이트/다크에서 유지됨.

### Implementation for User Story 1

- [X] T009 [P] [US1] `Common/UI/DesignSystem/DrawerActionButton.swift` — primary/secondary/destructive 변형과 normal/pressed/disabled/loading 상태를 토큰화, 강조색 `accent` 사용, `adjustsFontForContentSizeCategory = true` 적용 (contracts C1)
- [X] T010 [P] [US1] `Common/UI/DesignSystem/DrawerIconButton.swift` — 기본 tint 중립(`secondaryLabel`), 활성/선택 시 accent, 44pt 히트영역 보장 (contracts C2)
- [X] T011 [P] [US1] `Common/UI/DesignSystem/DrawerListCell.swift` — 토큰 폰트(Dynamic Type)·min-height 성장 허용·selected 시 accent 표시 (contracts C4)
- [X] T012 [P] [US1] `Common/UI/DesignSystem/DrawerHeaderView.swift` — 좌 back/close·중앙 제목 표준화, 토큰·구분선 정렬 (contracts C3)
- [X] T013 [P] [US1] `Common/UI/DesignSystem/DrawerSectionHeaderView.swift` 및 `DrawerSeparator.swift` — 토큰 정렬, accent 절제 (contracts C5/C6)
- [X] T014 [P] [US1] `Common/UI/DesignSystem/SearchBarView.swift` — placeholder/active 변형, secondary 배경·medium 곡률 토큰 정렬, Dynamic Type (contracts C7)
- [X] T015 [US1] `Common/UI/DesignSystem/` 전체에 `adjustsFontForContentSizeCategory` 누락 라벨 보강 및 인라인 폰트/하드코딩 색 잔재 제거 감사 (SC-001/SC-009)
- [X] T016 [US1] 공통 컴포넌트 세트 라이트/다크 + Dynamic Type 1단계 확대 시각 검증(컴포넌트 갤러리 또는 대표 화면 1개로) — 겹침·잘림 0건 확인 (SC-003/SC-006)

**Checkpoint**: 공유 컴포넌트가 단일 디자인 언어로 통일됨 → 이를 쓰는 화면들이 즉시 통일 인상 확보 (MVP)

---

## Phase 4: User Story 2 - 애플 지도풍의 깔끔한 주요 화면 (Priority: P2)

**Goal**: 사용 빈도 높은 홈/지도·검색·경로 미리보기를 애플 지도풍으로 정돈(플로팅 컨트롤 최소화, 표준 detent 시트, 빈/로딩 상태 통일).

**Independent Test**: 홈/지도·검색·경로 미리보기를 애플 지도와 병치 비교 시 여백·계층·시트·플로팅 컨트롤이 정돈됨.

### Implementation for User Story 2

- [X] T017 [US2] `Feature/Home/MapControlButtonsView.swift` — 상시 노출 컨트롤 최소화·그룹화(현재 위치 상시 / 레이어·새로고침 등 저빈도는 단일 메뉴 진입점), 토큰·불투명 카드 정렬 (FR-007b, research D6)
- [X] T018 [US2] `Feature/Home/HomeDrawerViewController.swift` — 표준 detent(`.peek/.half/.full`)·DrawerHeaderView·DrawerSectionHeaderView·DrawerListCell 정렬 (screen-inventory S1)
- [X] T019 [P] [US2] `Feature/Home/FavoriteCell.swift`, `Feature/Home/CategoryCell.swift`, `Feature/Home/RecentSearchCell.swift` — 토큰 폰트/색/간격 정렬, accent 절제 (S1)
- [X] T020 [P] [US2] `Map/MapViewController.swift` — 지도 위 잔존 하드코딩 색/오버레이 tint를 토큰으로 정렬(인스코프 한정, 주행 오버레이 제외) (S1)
- [X] T021 [US2] `Feature/Search/SearchViewController.swift` — 쿼리 칩 간격 등 매직 패딩 → `Theme.Spacing`, SearchBarView 사용, 토큰 정렬 (S2)
- [X] T022 [US2] `Feature/Search/SearchResultDrawerViewController.swift` + `Feature/Search/SearchResultCell.swift` — DrawerListCell/구분선 정렬, 결과 없음·로딩에 `EmptyStateView` 적용 (S2, FR-010)
- [X] T023 [US2] `Feature/RoutePreview/RoutePreviewDrawerViewController.swift` — 이동수단 Segment·구분선·시작/가상주행 버튼을 primary 단일 핵심 액션(accent)으로 정렬, 표준 detent (S3)
- [X] T024 [P] [US2] `Feature/RoutePreview/RouteOptionCell.swift` — 인라인 폰트(`UIFont.systemFont(ofSize:`) → `Theme.Fonts`, 토큰 정렬 (S3)

**Checkpoint**: 주요 화면이 애플 지도풍으로 정돈됨 — US1과 함께 독립 동작

---

## Phase 5: User Story 3 - 상세·대중교통·설정 화면의 마감 일관성 (Priority: P3)

**Goal**: 상세 시트·버스 노선/시간표·설정 화면을 동일 디자인 언어로 마감.

**Independent Test**: 각 상세/보조 화면에서 헤더·섹션·셀·구분선·버튼이 공통 컴포넌트 규칙을 따르고 임시 스타일이 없음.

### Implementation for User Story 3

- [X] T025 [US3] `Feature/MapItemDetail/MapItemDetailViewController.swift` — 표준 detent(`.peek/.half/.full`)·DrawerHeaderView 정렬, 콘텐츠 스캐폴드 토큰화 (S4)
- [X] T026 [P] [US3] `Feature/MapItemDetail/Content/PlaceContentView.swift` — 섹션/행/헤더 공통 스타일 정렬, 토큰 폰트·간격 (S4)
- [X] T027 [P] [US3] `Feature/MapItemDetail/Content/BikeStationContentView.swift` — 토큰 정렬, 따릉이 brand색은 도메인 의미색으로 한정(accent와 구분) (S4)
- [X] T028 [P] [US3] `Feature/MapItemDetail/Content/BusStopContentView.swift` — 노선색은 도메인 의미색 한정, 나머지 토큰 정렬, 도착정보 없음 `EmptyStateView` (S4/S5)
- [X] T029 [US3] `Feature/Transit/BusRouteDrawerViewController.swift` — DrawerHeaderView·DrawerListCell·SectionHeader 정렬, 표준 detent (S5)
- [X] T030 [US3] `Feature/Transit/BusStopTimetableDrawerViewController.swift` — 노선 라벨 인라인 폰트(17 semibold) → `Theme.Fonts.headline`, 도착정보 없음 `EmptyStateView` (S5)
- [X] T031 [US3] `Feature/Settings/SettingsViewController.swift` — 차량 아이콘 테두리 `systemGray4` → `Theme.Colors.separator`, 섹션/행 그룹 스타일·간격·Table 토큰 정렬, accent 절제 (S6)
- [X] T032 [P] [US3] `Feature/Settings/Vehicle3DImportViewController.swift` — 버튼·라벨·간격 토큰 정렬 (S6)

**Checkpoint**: 모든 인스코프 화면이 통일 디자인으로 마감됨

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 전 스토리 마감 후 통합 검증 및 범위 회귀 확인

- [X] T033 [P] 범위 회귀 확인: 주행화면(`Feature/Navigation/*`)·`Feature/DevTools/*`·`Feature/CarPlay/*` 모양·동작 무변경 확인 (SC-005)
- [X] T034 라이트/다크 + Dynamic Type 1단계 확대로 인스코프 전 화면 순회 검증 — 겹침·잘림·통일성 (quickstart §4–5, SC-003/SC-006)
- [X] T035 빈/로딩 상태 일관성 최종 점검: 검색 결과 없음·즐겨찾기/최근기록 없음·도착정보 없음·로딩이 `EmptyStateView`로 통일 (SC-007)
- [X] T036 액센트 절제·하드코딩 0건 최종 감사: 인스코프 grep 재실행으로 `UIColor(`/`.blue`/`systemGray`/`UIFont.systemFont(ofSize:` 잔재 0건 확인 (SC-001/SC-009)
- [X] T037 변경 전/후(및 애플 지도 병치) 스크린샷 비교로 "하나의 통일된 깔끔한 앱" 정성 합격 확인 (SC-004), `quickstart.md` 전체 체크리스트 수행
- [ ] T038 [P] (선택) accent/typography 토큰 매핑·WCAG 대비에 대한 경량 회귀 테스트(Swift Testing) 보강

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 즉시 시작 가능
- **Foundational (Phase 2)**: Setup(특히 T001 자산) 완료에 의존 — **모든 스토리 차단**
- **User Stories (Phase 3–5)**: 모두 Foundational 완료에 의존
  - US1(P1)은 공유 컴포넌트 계층 → US2/US3가 이 컴포넌트를 사용하므로 **US1 우선 권장**
  - US2·US3는 서로 다른 화면 파일 → US1 완료 후 병렬 가능
- **Polish (Phase 6)**: 원하는 스토리 완료 후

### User Story Dependencies

- **US1 (P1)**: Foundational 후 시작. 공유 컴포넌트 기반 → US2/US3의 선행 권장
- **US2 (P2)**: Foundational(+US1 컴포넌트) 후. US3와 독립
- **US3 (P3)**: Foundational(+US1 컴포넌트) 후. US2와 독립

### Within Each User Story

- 공통 컴포넌트(US1) → 이를 사용하는 화면(US2/US3) 순
- 같은 파일을 만지는 태스크는 순차, 다른 파일은 [P] 병렬

---

## Parallel Opportunities

- **Phase 1**: T002 [P]
- **Phase 2**: T005, T006, T008 [P] (T003·T004·T007은 Theme/Component 파일 공유 가능성 — 순차 권장)
- **Phase 3 (US1)**: T009–T014 모두 서로 다른 컴포넌트 파일 → [P] 병렬
- **Phase 4 (US2)**: T019, T020, T024 [P] (T017/T018/T021/T022/T023은 각 화면 단위 순차)
- **Phase 5 (US3)**: T026, T027, T028, T032 [P]
- **Phase 6**: T033, T038 [P]

### Parallel Example: User Story 1

```bash
# US1 공통 컴포넌트 — 서로 다른 파일이라 동시 진행:
Task: "DrawerActionButton.swift 토큰·상태화 (T009)"
Task: "DrawerIconButton.swift tint 중립/accent (T010)"
Task: "DrawerListCell.swift Dynamic Type·min-height (T011)"
Task: "DrawerHeaderView.swift 표준화 (T012)"
Task: "DrawerSectionHeaderView.swift + DrawerSeparator.swift (T013)"
Task: "SearchBarView.swift 변형·토큰 (T014)"
```

---

## Implementation Strategy

### MVP First (US1)

1. Phase 1 Setup → 2. Phase 2 Foundational(토큰·프리셋·EmptyStateView) → 3. Phase 3 US1(공유 컴포넌트 통일)
4. **STOP & VALIDATE**: 공통 컴포넌트를 쓰는 화면이 통일 인상을 갖는지 시각 검증
5. 데모/검수

### Incremental Delivery

1. Setup + Foundational → 기반 완료
2. US1 → 공유 컴포넌트 통일 (MVP, 즉시 체감)
3. US2 → 주요 화면 애플 지도풍 정돈
4. US3 → 상세·대중교통·설정 마감
5. Polish → 회귀·접근성·스크린샷 검증

---

## Notes

- [P] = 다른 파일·무의존 / [Story] = 추적용 스토리 라벨
- 본 작업은 시각 변경 → 각 체크포인트에서 시뮬레이터(`iPhone 17 Pro`, iOS 26) 시각 검증
- 주행화면·DevTools·CarPlay는 **동결** — 만지지 말 것(회귀 0건)
- 색은 항상 토큰 경유, accent는 절제(주요 액션·선택·링크), 표면은 불투명 솔리드
- 태스크/논리 그룹 단위로 커밋
