# Phase 1 Data Model: 디자인 토큰 & 컴포넌트 모델

**Feature**: 002-ui-design-refresh | **Date**: 2026-06-07

본 작업은 비즈니스 데이터 엔티티를 다루지 않는다. 여기서의 "모델"은 **디자인 토큰과 공통 컴포넌트의 단일 소스 구조**다. 모든 인스코프 화면은 이 모델만을 참조해야 한다(FR-001).

---

## 1. Token Groups (단일 소스: `Theme`)

### 1.1 Colors (`Theme.Colors`)
| 토큰 | 의미 | 변경 |
|------|------|------|
| `accent` (신규) | 강조색 — 주요 액션·선택/활성·링크 전용 | **신규**: 에셋 `AccentIndigo` (Light #4F46E5 / Dark #818CF8) |
| `accentSubtle` (선택) | 선택 배경 등 옅은 강조 | 신규(필요 시) |
| `background` | 기본 표면(드로어/화면) | 유지 (솔리드) |
| `secondaryBackground` | 보조 표면/입력 배경 | 유지 |
| `surface` | 카드 표면 | 유지 |
| `label` / `secondaryLabel` | 본문/보조 텍스트(중립) | 유지 |
| `separator` | 구분선 | 유지 |
| `destructive` / `success` | 의미색 | 유지 |
| `bikeBrand` | 따릉이 브랜드(도메인 예외색) | 유지 |

- **규칙**: 액센트는 §Accent Usage Rules 참조. 그 외 UI는 중립/의미색만 사용. 화면 내 `UIColor(...)` 직접 생성 금지(SC-001).

### 1.2 Typography (`Theme.Fonts`) — Dynamic Type 전환
| 토큰 | 매핑 텍스트 스타일 | 비고 |
|------|------------------|------|
| `largeTitle` | `.largeTitle` | 스케일 |
| `title` | `.title2` | 스케일 |
| `headline` | `.headline` | 스케일 |
| `body` | `.body` | 스케일 |
| `callout` | `.callout` | 스케일 |
| `subheadline` | `.subheadline` | 스케일 |
| `footnote` | `.footnote` | 스케일 |
| `caption` | `.caption1` | 스케일 |
| `maneuverDistance`/`maneuverInstruction`/`eta` | (고정) | **주행화면 전용 — 변경 없음** |

- **규칙**: 표시 라벨/버튼은 `adjustsFontForContentSizeCategory = true`. 인라인 `UIFont.systemFont(ofSize:)` 금지(인스코프).

### 1.3 Spacing (`Theme.Spacing`) — 유지
`xxs(2) xs(4) sm(8) md(12) lg(16) xl(24) xxl(32)`. 화면 내 매직 패딩 금지(FR-005).

### 1.4 CornerRadius (`Theme.CornerRadius`) — 유지
`small(8) medium(12) large(16) pill`. 임의 곡률(예: 14, 24) 금지 → 토큰으로 정렬.

### 1.5 IconSize / Shadow — 유지
아이콘 크기·그림자는 기존 토큰 사용. `Card.backgroundOpacity`는 1.0(불투명)으로 정렬(D3).

---

## 2. Detent Presets (신규: `DrawerDetent` 표준 세트)

전 화면 시트 통일을 위한 표준 detent. 식별자·비율을 프리셋으로 고정한다.

| 프리셋 | 정의 | 용도 |
|--------|------|------|
| `.peek` | fractional ~0.30 | 핸들+요약(예: 홈 기본, 상세 최초 노출) |
| `.half` | fractional ~0.55 | 목록 탐색(검색 결과, 노선 정류장) |
| `.full` | fractional ~0.92 | 집중 탐색/긴 목록 |

- 각 화면은 위 프리셋의 부분집합을 사용(예: 상세=[peek, half, full], 단순 액션 시트=[peek]).
- 구체 비율은 구현 시 디바이스 높이 기준 확정, 단일 정의 지점 유지.

---

## 3. Shared Components (단일 소스: `Common/UI/DesignSystem`)

각 컴포넌트는 **변형(variant)**과 **상태(state)**를 토큰으로 표현한다. 상세 계약은 `contracts/component-catalog.md`.

| 컴포넌트 | 변형 | 상태 | 상태(현행) |
|----------|------|------|-----------|
| `DrawerActionButton` | primary / secondary / destructive | normal / pressed / disabled / loading | 존재 — accent 정렬 |
| `DrawerIconButton` | close / back / favorite / settings / custom | normal / pressed / disabled | 존재 — tint 토큰화 |
| `DrawerHeaderView` | title / title+actions | — | 존재 |
| `DrawerListCell` | icon+title / +subtitle / +accessory | normal / selected | 존재 — 고정 height 완화 |
| `DrawerSectionHeaderView` | icon+title | — | 존재 |
| `DrawerSeparator` | fullWidth / inset | — | 존재 |
| `SearchBarView` | placeholder / active | — | 존재 |
| `EmptyStateView` | empty / loading | — | **신규**(D5) |
| `DrawerContainerView` | (그래버 + 솔리드 + 곡률) | — | 존재 — 변경 최소 |

---

## 4. Accent Usage Rules (FR-002a / SC-009)

| 허용(accent 사용) | 금지(중립/의미색 사용) |
|-------------------|----------------------|
| 주요 액션 버튼(시작/확인 등) 배경 | 일반 표면/배경 |
| 선택·활성 상태(세그먼트 선택, 셀 선택 표시) | 본문/제목 텍스트(기본) |
| 링크/탭 가능한 강조 텍스트 | 장식용 아이콘 다채색 |
| 진행/포커스 인디케이터 | 구분선·테두리(→ `separator`) |

위반 0건이 SC-009 합격 기준.

---

## 5. Scope Guard (모델 적용 경계)

- **적용**: 인스코프 화면(§spec In-Scope) 및 공유 컴포넌트.
- **미적용(동결)**: 주행화면(`Feature/Navigation/*`), DevTools, CarPlay — 토큰/컴포넌트 변경 금지(SC-005 회귀 0건).
