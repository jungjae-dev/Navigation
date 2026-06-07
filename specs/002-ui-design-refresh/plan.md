# Implementation Plan: 사용자 화면 디자인·레이아웃 통일 리팩토링

**Branch**: `002-ui-design-refresh` | **Date**: 2026-06-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-ui-design-refresh/spec.md`

## Summary

주행화면을 제외한 모든 사용자 화면을, 이미 존재하는 디자인 토큰(`Theme`)과 detent 기반 단일 드로어 시스템(`DrawerContainerManager`) 위로 일원화하여 애플 지도풍의 심플·통일·깔끔한 디자인으로 정리한다. 핵심은 새 프레임워크 도입이 아니라 **기존 자산의 단일 기준화 + 누락 갭 메우기**다.

코드 조사 결과 세 가지 핵심 갭이 확인됐다:
1. **강조색**: 현재 `Theme.Colors.primary = systemBlue`이며 인디고 액센트(#4F46E5/#818CF8)·`Theme.Palette`는 코드에 존재하지 않는다 → 에셋 카탈로그 기반 인디고 액센트 토큰을 도입하고 절제 사용 규칙을 정립한다.
2. **Dynamic Type 전무**: 모든 폰트가 고정 크기 `systemFont(ofSize:)`이며 `UIFontMetrics`/`adjustsFontForContentSizeCategory` 사용처가 0건이다 → `Theme.Fonts`를 텍스트 스타일 기반 스케일 폰트로 전환한다(FR-009).
3. **토큰 미준수 산재**: 화면별 하드코딩 색/폰트/간격이 잔존한다 → 인스코프 화면을 토큰·공통 컴포넌트로 흡수한다.

detent 드로어 컨테이너는 이미 불투명 솔리드 배경(`Theme.Colors.background`)·그래버·다단계 detent·스크롤 핸드오프를 갖추어 FR-006a/FR-007a를 인프라 수준에서 충족한다. 따라서 시트 관련 작업은 "각 인스코프 화면이 이 컨테이너를 일관되게 경유하는지 감사·정렬"로 한정된다.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)

**Primary Dependencies**: UIKit (programmatic), 일부 SwiftUI(상세 콘텐츠 뷰), Combine, MapKit. 외부 UI 라이브러리 없음.

**Storage**: N/A — 본 작업은 시각·레이아웃 한정, 데이터/영속화 변경 없음.

**Testing**: Swift Testing(`import Testing`). 단, 본 작업은 주로 **시뮬레이터 시각 검증**(라이트/다크, Dynamic Type, 스크린샷)으로 완료를 판정. 토큰 회귀 방지용 단위 테스트(예: 접근성 대비, 토큰 매핑)는 선택적으로 보강.

**Target Platform**: iOS 26 (Xcode 26), 시뮬레이터 `iPhone 17 Pro`

**Project Type**: 기존 iOS 모바일 앱 (UIKit + MVVM + Coordinator + Combine)

**Performance Goals**: 시트 드래그/스냅 60fps 유지, 기존 드로어 애니메이션(0.3s spring) 체감 유지.

**Constraints**: 주행화면·DevTools·CarPlay 미변경(회귀 0건). 기능·화면 흐름 보존, 레이아웃 재배치만 허용. 색은 항상 토큰 경유 + WCAG AA(4.5:1).

**Scale/Scope**: 인스코프 약 12개 화면/시트 + 공유 컴포넌트 ~10종. 공통 토큰 파일 4개(`Theme.swift`, `Theme+Component`, `Theme+Drawer`, 신규 accent/typography 보강).

## Constitution Check

*GATE: Phase 0 이전 통과 필요. Phase 1 이후 재검토.*

| 원칙 | 평가 | 비고 |
|------|------|------|
| I. Swift 6 Concurrency (NON-NEGOTIABLE) | ✅ Pass | 뷰 계층 스타일링 한정. delegate 패턴 변경 없음, 신규 동시성 도입 없음. |
| II. MVVM + Coordinator + Combine | ✅ Pass | ViewModel/Coordinator 로직 불변. View 레이어 토큰·레이아웃만 수정. `CurrentValueSubject` 패턴 유지. |
| III. 단순성 우선 (YAGNI) | ✅ Pass | **기존 `Theme`/`DrawerContainerManager` 재사용**, 신규 디자인 프레임워크·추상화 금지. 인디고 액센트/스케일 폰트는 현재 요구(FR-002a/FR-009)에 직접 대응하는 최소 변경. 미사용 토큰 추가 금지. |
| IV. 로그 기반 검증 | ⚠️ 적응 | 순수 시각 변경은 로그 포인트가 부적합. 원칙의 취지(빌드 성공이 아닌 **시뮬레이터 실측 검증**)를 **시뮬레이터 시각 확인(라이트/다크·Dynamic Type·스크린샷 비교)**으로 충족. 위반 아님. |
| V. iOS 26 / Xcode 26 대응 | ✅ Pass | `iPhone 17 Pro` 시뮬레이터. 시스템 색/폰트 메트릭 API 사용. |

**Architecture Constraints**: 싱글턴(`LocationService`, `NavigationSessionManager`) 불변. pbxproj 수동 참조 금지(auto-sync). API 키 불변. → 모두 영향 없음.

**Gate 결과**: PASS. 위반 없음 → Complexity Tracking 불필요.

## Project Structure

### Documentation (this feature)

```text
specs/002-ui-design-refresh/
├── plan.md              # This file
├── research.md          # Phase 0 — 디자인 결정(액센트/타이포/시트/빈상태)
├── data-model.md        # Phase 1 — 디자인 토큰 & 컴포넌트 모델
├── quickstart.md        # Phase 1 — 시각 검증 절차
├── contracts/
│   ├── component-catalog.md   # 공통 컴포넌트 계약(변형/상태/사용 규칙)
│   └── screen-inventory.md    # 인스코프 화면 ↔ 컴포넌트 매핑·감사 체크
├── checklists/
│   └── requirements.md  # (기존) 스펙 품질 체크리스트
└── tasks.md             # /speckit-tasks 산출물 (이 명령에서 생성 안 함)
```

### Source Code (repository root)

핵심 변경은 공통 UI 토큰/컴포넌트와 인스코프 화면 디렉터리에 집중된다.

```text
Navigation/Navigation/Common/UI/
├── Theme.swift                         # 토큰 단일 소스 — accent/typography 보강
├── DesignSystem/
│   ├── Theme+Component.swift           # 버튼/카드/세그먼트 등 컴포넌트 토큰
│   ├── Theme+Drawer.swift              # 드로어 헤더/셀/검색바 토큰
│   ├── DrawerActionButton.swift        # 공통 버튼 (재사용)
│   ├── DrawerIconButton.swift          # 공통 아이콘 버튼
│   ├── DrawerHeaderView.swift          # 공통 헤더
│   ├── DrawerListCell.swift            # 공통 목록 셀
│   ├── DrawerSectionHeaderView.swift   # 섹션 헤더
│   ├── DrawerSeparator.swift           # 구분선
│   ├── SearchBarView.swift             # 검색 바
│   └── EmptyStateView.swift (신규)     # 공통 빈 상태/로딩 표현 (FR-010)
├── DrawerContainerManager.swift        # detent 단일 시트 (재사용, 변경 최소)
├── DrawerContainerView.swift           # 불투명 솔리드 + 그래버 (재사용)
├── DrawerDetent.swift                  # detent 정의 (재사용)
└── GrabberView.swift                   # 그래버 (재사용)

Navigation/Navigation/Feature/        # 인스코프 화면(토큰·컴포넌트로 정렬)
├── Home/ (HomeViewController, HomeDrawerViewController, 셀들)
├── Search/ (SearchViewController, SearchResultDrawerViewController, 셀)
├── RoutePreview/ (RoutePreviewDrawerViewController, RouteOptionCell)
├── MapItemDetail/ (MapItemDetailViewController + Content/*)
├── Transit/ (BusRouteDrawerViewController, BusStopTimetableDrawerViewController)
├── Settings/ (SettingsViewController, Vehicle3DImportViewController)
└── Map/ (MapViewController, MapControlButtonsView)   # 플로팅 컨트롤 최소화·그룹화

# 미변경(Out-of-scope): Feature/Navigation/* (주행), Feature/DevTools/*, Feature/CarPlay/*
```

**Structure Decision**: 기존 단일 iOS 앱 구조를 유지한다. 변경은 `Common/UI`(토큰·공통 컴포넌트)와 `Feature/*`(인스코프 화면)에 국한하며, 새 모듈/타깃은 만들지 않는다. 디자인 일원화의 "단일 소스"는 `Theme`와 `Common/UI/DesignSystem` 자산이다.

## Complexity Tracking

> Constitution Check 위반 없음 — 해당 없음.
