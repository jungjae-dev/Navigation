# Contract: 공통 컴포넌트 카탈로그 (UI Contract)

**Feature**: 002-ui-design-refresh | **Date**: 2026-06-07

인스코프 화면이 따라야 하는 공통 컴포넌트의 "계약"이다. 각 항목은 **반드시 토큰만 사용**하며, 화면은 이 컴포넌트를 조합해 구성한다. 새 화면 전용 변형을 임의 추가하지 않는다(필요 시 카탈로그에 먼저 반영).

---

## C1. DrawerActionButton
- **변형**: `primary`(accent 배경/흰 텍스트), `secondary`(보조 배경/accent 텍스트), `destructive`(destructive 배경/흰 텍스트).
- **상태**: `normal`, `pressed`(눌림 피드백), `disabled`(저대비), `loading`(인디케이터, 라벨 숨김/비활성).
- **토큰**: `Theme.Button.*`, 색은 `Theme.Colors.accent`/`destructive`/`secondaryBackground`.
- **계약**: height·corner·font는 토큰 고정. 임의 색/크기 금지. 주요 화면당 primary 액션은 1개 권장(애플 지도식 단일 핵심 액션).

## C2. DrawerIconButton
- **변형**: `close`, `back`, `favorite`, `settings`, `custom(systemName:)`.
- **상태**: `normal`, `pressed`, `disabled`.
- **토큰**: tint = `Theme.Colors.secondaryLabel`(중립) 기본, 활성/선택 시 `accent`. 최소 히트영역 44pt.
- **계약**: 장식 아이콘에 accent 남용 금지(중립 우선).

## C3. DrawerHeaderView
- **변형**: `title`(중앙 제목), `title+actions`(좌/우 아이콘 버튼 슬롯).
- **토큰**: `Theme.Drawer.Header.*`. 하단 전폭 구분선 옵션.
- **계약**: 모든 시트 상단은 이 헤더로 통일(좌측 back/close, 중앙 제목). 화면별 임의 헤더 금지.

## C4. DrawerListCell
- **변형**: `icon+title`, `icon+title+subtitle`, `+accessory`(우측 체크/디스클로저).
- **상태**: `normal`, `selected`(선택 시 accent 표시).
- **토큰**: `Theme.Drawer.Cell.*`. 아이콘 컨테이너 곡률 small.
- **계약**: height는 **최소 height**로 취급(Dynamic Type 확대 시 성장 허용). 검색/즐겨찾기/노선/정류장/설정 행은 본 셀로 통일.

## C5. DrawerSectionHeaderView
- **변형**: `icon+title`.
- **토큰**: `Theme.Drawer.SectionHeader.*`. 아이콘 tint accent는 절제(섹션 의미 강조에 한함) 또는 중립.

## C6. DrawerSeparator
- **변형**: `fullWidth`, `inset`(좌우 `lg` 인셋).
- **토큰**: `Theme.Colors.separator`, 1px.

## C7. SearchBarView
- **변형**: `placeholder`(탭 진입용), `active`(입력).
- **토큰**: `Theme.Drawer.SearchBar.*`. 배경 secondary, 곡률 medium.
- **계약**: 홈/검색의 검색 진입은 본 컴포넌트로 통일.

## C8. EmptyStateView (신규)
- **변형**: `empty`(아이콘+제목+부제), `loading`(인디케이터+선택적 캡션).
- **토큰**: 아이콘 `IconSize.xxxl`/중립 tint, 제목 `Fonts.headline`, 부제 `Fonts.footnote`/`secondaryLabel`.
- **계약**: "검색 결과 없음 / 즐겨찾기·최근기록 없음 / 도착정보 없음 / 로딩 중"을 본 컴포넌트로 통일(FR-010).

## C9. DrawerContainerView (시트 표면)
- **속성**: 불투명 솔리드(`Colors.background`), 곡률 `large`, 상단 그래버, 다단계 detent(C-presets).
- **계약**: 모든 하단 시트는 본 컨테이너 + `DrawerContainerManager` 경유. 반투명/머터리얼 금지. 화면별 커스텀 시트 금지(SC-008).

---

## 컴포넌트 상태 매트릭스(검증 기준)

| 컴포넌트 | normal | pressed | disabled | loading | selected |
|----------|:------:|:-------:|:--------:|:-------:|:--------:|
| ActionButton | ✅ | ✅ | ✅ | ✅ | — |
| IconButton | ✅ | ✅ | ✅ | — | ✅(활성) |
| ListCell | ✅ | — | — | — | ✅ |
| EmptyState | ✅(empty) | — | — | ✅ | — |

각 ✅ 상태는 라이트/다크 모두에서 토큰 기반으로 표현되어야 한다.
