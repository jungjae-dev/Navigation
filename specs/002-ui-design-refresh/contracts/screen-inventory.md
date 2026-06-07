# Contract: 인스코프 화면 ↔ 컴포넌트 매핑 · 감사 체크

**Feature**: 002-ui-design-refresh | **Date**: 2026-06-07

인스코프 각 화면이 사용해야 할 공통 컴포넌트와, 토큰 미준수 감사 항목이다. tasks 분해 시 화면 단위 작업의 기준.

감사 공통 항목(모든 화면 적용):
- [ ] 하드코딩 색 제거 (`UIColor(...)`, `.blue`, `systemGray*`) → 토큰
- [ ] 인라인 폰트 제거 (`UIFont.systemFont(ofSize:)`) → `Theme.Fonts` (Dynamic Type)
- [ ] 매직 패딩/곡률 제거 → `Theme.Spacing` / `Theme.CornerRadius`
- [ ] 라이트/다크 + Dynamic Type 1단계 확대 시 깨짐 없음
- [ ] accent 절제 규칙 준수(주요 액션·선택·링크 한정)

---

## S1. 홈/지도 (`Home/`, `Map/`)
- **파일**: `HomeViewController`, `HomeDrawerViewController`, `FavoriteCell`, `CategoryCell`, `RecentSearchCell`, `MapViewController`, `MapControlButtonsView`
- **컴포넌트**: DrawerContainerView(peek/half/full), DrawerHeaderView, SearchBarView, DrawerSectionHeaderView, DrawerListCell, FavoriteCell
- **화면 특이 작업**:
  - [ ] 플로팅 컨트롤 최소화·그룹화(현재 위치 상시 / 레이어·새로고침 그룹화) — FR-007b
  - [ ] 홈 드로어를 표준 detent·헤더·셀로 정렬

## S2. 검색 (`Search/`)
- **파일**: `SearchViewController`, `SearchResultDrawerViewController`, `SearchResultCell`
- **컴포넌트**: SearchBarView, DrawerListCell, DrawerSeparator, EmptyStateView(결과 없음/로딩)
- **화면 특이 작업**:
  - [ ] 쿼리 칩 간격 `Theme.Spacing` 정렬(현 하드코딩 8)
  - [ ] 결과 없음/로딩 EmptyStateView 적용

## S3. 경로 미리보기 (`RoutePreview/`)
- **파일**: `RoutePreviewDrawerViewController`, `RouteOptionCell`
- **컴포넌트**: DrawerHeaderView, Segment(이동수단), DrawerListCell/RouteOptionCell, DrawerActionButton(primary=시작), DrawerSeparator
- **화면 특이 작업**:
  - [ ] RouteOptionCell 인라인 폰트 → 토큰
  - [ ] 시작/가상주행 버튼 primary 단일화·accent 정렬

## S4. 상세 시트 (`MapItemDetail/`)
- **파일**: `MapItemDetailViewController`, `Content/PlaceContentView`, `BikeStationContentView`, `BusStopContentView`
- **컴포넌트**: DrawerContainerView(peek/half/full), DrawerHeaderView, DrawerSectionHeaderView, DrawerListCell, DrawerActionButton
- **화면 특이 작업**:
  - [ ] 3종 콘텐츠(장소/대여소/정류장) 헤더·섹션·행 스타일 통일
  - [ ] 따릉이 brand/버스 노선색은 도메인 의미색으로 한정(액센트와 구분)

## S5. 대중교통 (`Transit/`)
- **파일**: `BusRouteDrawerViewController`, `BusStopTimetableDrawerViewController`
- **컴포넌트**: DrawerHeaderView, DrawerListCell, DrawerSectionHeaderView, EmptyStateView(도착정보 없음)
- **화면 특이 작업**:
  - [ ] 시간표 노선 라벨 인라인 폰트(17 semibold) → `Theme.Fonts.headline`
  - [ ] 도착정보 없음 EmptyStateView 적용

## S6. 설정 (`Settings/`)
- **파일**: `SettingsViewController`, `Vehicle3DImportViewController`
- **컴포넌트**: Table 토큰(셀/디테일), DrawerActionButton, DrawerSeparator
- **화면 특이 작업**:
  - [ ] 차량 아이콘 테두리 `systemGray4` → `Theme.Colors.separator`
  - [ ] 섹션/행 그룹 스타일·간격 통일

---

## 동결(미변경) — 회귀 검증만
- 주행화면 `Feature/Navigation/*`, `DevTools/*`, `CarPlay/*` — 토큰/레이아웃 변경 금지. SC-005 회귀 0건 확인.

---

## 감사 베이스라인 (T002, 2026-06-07)

인스코프 하드코딩/인라인 현황(grep). 동결 파일(`Theme+Navigation.swift` 주행 토큰, `Theme+Component` Playback)은 제외.

**하드코딩 색**
- `Feature/Settings/SettingsViewController.swift:390` — `UIColor.systemGray4.cgColor`(차량 아이콘 테두리) → `separator` (T031)
- `Map/MapViewController.swift:212,743,879` — 비포커스 마커 `.systemGray`(중립, 허용) / 포커스 `Theme.Colors.primary` → accent 정렬 (T020)
- `Map/Annotation/BusStopAnnotationView.swift:25` — 버스 정류장 마커 하드코딩 `#3366CC` → 도메인 의미색 토큰화 검토 (T020)
- `Common/UI/Theme.swift:18` — `bikeBrand`(도메인 브랜드색, 의도된 예외 — 유지)

**인라인 폰트(→ Dynamic Type 토큰)**
- `Common/UI/Theme.swift:24-31` — 본문 계열 전체 (T004에서 일괄 전환)
- `Feature/MapItemDetail/Content/BikeStationContentView.swift:32` — `monospacedDigit 28 bold`(대수 표시) → 스케일 모노 (T027)
- `Feature/MapItemDetail/Content/BusStopContentView.swift:136` — `17 semibold` → `Fonts.headline` (T028)
- `Feature/Transit/BusRouteDrawerViewController.swift:140` — `17 semibold` → `Fonts.headline` (T029)
- `Feature/Transit/BusStopTimetableDrawerViewController.swift:164` — `17 semibold` → `Fonts.headline` (T030)

**매직 곡률**: 인스코프 0건(이미 토큰 사용).
