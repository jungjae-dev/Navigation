# 홈 화면 리팩토링 & 디자인 시스템 구축

## 작업 목적

- 홈 화면의 검색바를 HomeDrawer 헤더로 이동
- 모든 드로어의 상단 고정 영역(헤더)을 통일된 구조로 개선
- 앱 전체에 적용 가능한 디자인 시스템(토큰 + 공통 컴포넌트) 구축
- 하드코딩된 매직넘버를 시맨틱 토큰으로 교체

## 작업 단계 (6단계)

| 단계 | 내용 | 문서 |
|------|------|------|
| Phase 1 | 디자인 시스템 토큰 정의 | [01_design_tokens.md](01_design_tokens.md) |
| Phase 2 | 공통 UI 컴포넌트 생성 | [02_common_components.md](02_common_components.md) |
| Phase 3 | 홈 화면 구조 변경 | [03_home_restructure.md](03_home_restructure.md) |
| Phase 4 | 드로어 공통 컴포넌트 적용 | [04_drawer_unification.md](04_drawer_unification.md) |
| Phase 5 | 주행/설정/재생 화면 토큰 적용 | [05_other_screens.md](05_other_screens.md) |
| Phase 6 | 매직넘버 정리 및 검증 | [06_cleanup.md](06_cleanup.md) |

## 파일 구조 (신규 생성)

```
Common/UI/DesignSystem/
├── Theme+Drawer.swift        (드로어 시맨틱 토큰)
├── Theme+Component.swift     (전체 화면 공통 시맨틱 토큰)
├── DrawerHeaderView.swift    (드로어 헤더)
├── DrawerSectionHeaderView.swift (섹션 헤더)
├── DrawerListCell.swift      (범용 리스트 셀)
├── DrawerActionButton.swift  (CTA 버튼)
├── DrawerIconButton.swift    (원형 아이콘 버튼)
├── DrawerSeparator.swift     (구분선)
├── SearchBarView.swift       (검색바)
└── OverlayContainer.swift    (반투명 배경 컨테이너)
```

## 수정 대상 파일

```
Common/UI/
├── Theme.swift                        (기존 토큰 보완)
├── DrawerContainerView.swift          (변경 없음)
├── DrawerContainerManager.swift       (detent 계산 변경)
├── GrabberView.swift                  (변경 없음)

Feature/Home/
├── HomeViewController.swift           (검색바/설정 제거, detent 조정)
├── HomeDrawerViewController.swift     (헤더 추가, 검색바+설정 배치)
├── RecentSearchCell.swift             (DrawerListCell로 대체 검토)
├── HomeSectionHeaderView.swift        (DrawerSectionHeaderView로 대체 검토)

Feature/Search/
├── SearchResultDrawerViewController.swift  (DrawerHeaderView 적용)
├── SearchResultCell.swift                  (DrawerListCell로 대체 검토)

Feature/POIDetail/
├── POIDetailViewController.swift      (DrawerHeaderView 적용)

Feature/RoutePreview/
├── RoutePreviewDrawerViewController.swift  (DrawerHeaderView 적용)
├── RouteOptionCell.swift                   (스타일 토큰 적용)

Feature/Navigation/
├── NavigationViewController.swift     (토큰 적용)
├── PlaybackControlView.swift          (토큰 적용)

Feature/Settings/
├── SettingsViewController.swift       (토큰 적용)

Feature/DevTools/
├── DevToolsViewController.swift       (토큰 적용)

Coordinator/
├── AppCoordinator.swift               (detent 계산 변경)
```
