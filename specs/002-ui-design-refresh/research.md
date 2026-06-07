# Phase 0 Research: 디자인·레이아웃 통일 리팩토링

**Feature**: 002-ui-design-refresh | **Date**: 2026-06-07

본 작업은 외부 기술 도입이 아닌 **기존 코드 자산의 정렬**이므로, 연구는 코드베이스 현황 분석과 디자인 결정에 집중한다. 모든 NEEDS CLARIFICATION은 스펙의 Clarifications(2026-06-07)에서 해소됨.

---

## D1. 강조색(액센트) — 인디고 토큰 도입

- **Decision**: 에셋 카탈로그에 `AccentIndigo` 색상 세트(Any: #4F46E5 / Dark: #818CF8)를 추가하고, `Theme.Colors`에 `accent`(및 필요 시 `accentSubtle`)로 노출한다. 기존 `Theme.Colors.primary`가 액센트 의미로 쓰이던 지점을 `accent`로 정렬한다. 액센트는 **주요 액션·선택/활성·링크에만** 사용하고, 그 외 표면/아이콘/텍스트는 중립색(`label`/`secondaryLabel`/`separator`)을 쓴다.
- **Rationale**: 현재 `Theme.Colors.primary = systemBlue`이고 인디고·`Theme.Palette`는 코드에 **존재하지 않음**(grep 확인: `systemIndigo`는 주석/DevTools에만). 메모리의 디자인 의도(인디고 액센트, 항상 토큰 경유, WCAG AA)를 실제 토큰으로 구현하는 것이 이번 작업의 일부다. 에셋 카탈로그 색상 세트는 라이트/다크 자동 전환과 대비 관리를 단일 지점에서 제공한다.
- **Alternatives considered**:
  - `Theme.Palette` 신설(메모리 명명) — 기존 코드는 `Theme.Colors` 네임스페이스를 일관되게 사용. YAGNI·일관성 위해 **`Theme.Colors` 유지**, Palette 명명은 도입하지 않음(불필요한 이중 네임스페이스 방지).
  - 코드 내 `UIColor(red:…)` 하드코딩 — 라이트/다크 분기·대비 검증이 분산되어 거부.
- **WCAG**: 라이트 #4F46E5(흰 텍스트 위 대비 양호), 다크 #818CF8(검정/다크 표면 위) 모두 액션 버튼·링크 텍스트 기준 AA 충족을 검증(quickstart 절차 포함).

## D2. 타이포그래피 — Dynamic Type 전환

- **Decision**: `Theme.Fonts`의 본문/제목/캡션 계열을 `UIFontMetrics(forTextStyle:).scaledFont(for:)` 기반 스케일 폰트로 전환하고, 텍스트를 표시하는 라벨/버튼에 `adjustsFontForContentSizeCategory = true`를 설정한다. 각 토큰을 의미적 텍스트 스타일에 매핑(예: title→`.title2`, headline→`.headline`, body→`.body`, footnote→`.footnote`, caption→`.caption1`).
- **Rationale**: 현재 모든 폰트가 고정 크기(`systemFont(ofSize:weight:)`)이며 Dynamic Type 사용처 0건(grep 확인). FR-009·SC-006(한 단계 확대 시 깨짐 0건)을 충족하려면 스케일 폰트가 필수. 토큰 단일 지점 전환이 화면별 수정보다 효율적이고 통일성을 보장.
- **Alternatives considered**:
  - 화면별 개별 `preferredFont` 적용 — 산재·누락 위험으로 거부. 토큰 일괄 전환이 우월.
  - 주행화면 전용 글랜스 폰트(`maneuverDistance` 등)는 **고정 유지**(주행화면 out-of-scope, 안전상 고정 크기 의도).
- **주의**: 스케일 폰트 전환 시 고정 height 가정(셀 52pt, 헤더 44pt 등)이 큰 글자에서 잘릴 수 있음 → 고정 height를 최소 height로 완화하거나 `intrinsicContentSize` 기반으로 조정(화면별 감사 항목).

## D3. 표면 재질 — 불투명 솔리드(확정)

- **Decision**: 드로어/플로팅 표면은 불투명 솔리드 유지. `DrawerContainerView.backgroundColor = Theme.Colors.background`가 이미 솔리드이므로 **변경 불필요**. 플로팅 `Card` 토큰의 `backgroundOpacity = 0.9`는 솔리드 원칙에 맞춰 **1.0(불투명)**로 정렬.
- **Rationale**: Clarification 결과 "불투명 솔리드". 블러/머터리얼 미사용으로 대비·가독성·구현 단순성 우선. `Card.backgroundOpacity 0.9`만이 반투명 잔재라 정렬 대상.
- **Alternatives considered**: 반투명 머터리얼(애플 지도 기본) — 사용자가 명시적으로 솔리드 선택, 거부.

## D4. 시트 패턴 — 기존 detent 컨테이너 일원화

- **Decision**: 신규 시트 시스템을 만들지 않고 `DrawerContainerManager`(그래버 + 다단계 detent + 스크롤 핸드오프)를 **유일한 하단 시트 패턴**으로 채택. 각 인스코프 화면이 표준 detent 세트(예: small/medium/large fractional)를 사용하도록 감사·정렬. 드로어가 아닌 화면(예: 설정이 push/modal이라면)은 화면 흐름 보존 범위에서 시각 토큰만 정렬(시트 강제 변환은 흐름을 바꾸지 않는 한도).
- **Rationale**: FR-007a 요구가 인프라 수준에서 이미 충족(컨테이너·그래버·detent 존재). 재구현은 YAGNI 위반. 작업은 "일관된 경유·일관된 detent·일관된 헤더/콘텐츠 패딩"으로 수렴.
- **Alternatives considered**: `UISheetPresentationController` 표준 시트로 교체 — 기존 커스텀 매니저가 스택/스크롤 핸드오프 등 앱 특화 동작을 이미 제공하므로 교체 비용 대비 이득 없음. 거부.
- **Open item(설계 단계 확정)**: 표준 detent 식별자·비율을 `DrawerDetent` 프리셋으로 정의해 화면 간 통일(data-model에 기재).

## D5. 빈 상태/로딩 — 공통 컴포넌트 신설

- **Decision**: `Common/UI/DesignSystem/EmptyStateView.swift`를 신설(아이콘 + 제목 + 선택적 부제). 로딩은 표준 `UIActivityIndicatorView`를 토큰 색으로 통일하거나 동일 컴포넌트의 로딩 변형으로 제공. 검색 결과 없음/즐겨찾기·최근기록 없음/도착정보 없음에 일관 적용(FR-010, SC-007).
- **Rationale**: 현재 빈/로딩 표현이 화면별로 제각각이거나 부재. 단일 컴포넌트가 통일성과 재사용을 보장. YAGNI 범위 내(실제 발생 케이스만).
- **Alternatives considered**: 화면별 임시 라벨 — 통일성 위반, 거부.

## D6. 플로팅 컨트롤 최소화·그룹화

- **Decision**: 홈/지도의 상시 노출 `MapControlButtonsView`(현재 위치·지도 모드·POI 레이어·따릉이 새로고침)를 애플 지도 수준으로 축소: 자주 쓰는 핵심(현재 위치)만 상시 노출하고, 저빈도 항목(레이어 토글·새로고침 등)은 단일 "레이어/더보기" 진입점(메뉴 또는 시트)으로 그룹화. 기능 접근성은 보존(항목 재배치 허용, 제거 아님).
- **Rationale**: FR-007b·SC(지도 가시영역 확대). 기능 흐름 보존 제약 하에서 "재배치"만 수행.
- **Alternatives considered**: 버튼 제거 — 기능 손실이라 거부. 전부 상시 노출 유지 — 깔끔함 목표 미달, 거부.

## D7. 토큰 미준수 감사 방식

- **Decision**: 인스코프 화면을 대상으로 (a) 하드코딩 색(`UIColor(...)`, `.blue`, `systemGray*`), (b) 인라인 폰트(`UIFont.systemFont(ofSize:`), (c) 매직 패딩/곡률을 grep 기반으로 식별해 토큰으로 치환. `screen-inventory.md`에 화면별 체크 항목으로 관리.
- **Rationale**: SC-001/SC-009(하드코딩 0건, 액센트 절제 위반 0건) 측정 가능화. 감사 목록이 tasks 분해의 기준이 됨.
- **Alternatives considered**: 린트 규칙 자동화(예: 커스텀 SwiftLint 룰) — 현 범위엔 과함(YAGNI). 수동 감사 + grep으로 충분.

---

## 미해결 항목

없음. 모든 결정이 스펙·Clarifications·코드 현황으로 확정됨. 표준 detent 프리셋의 구체 수치는 Phase 1 data-model에서 정의.
