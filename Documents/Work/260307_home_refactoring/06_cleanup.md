# Phase 6: 매직넘버 정리 및 검증

## 목표

- 전체 코드에서 남아있는 하드코딩 매직넘버를 찾아 토큰으로 교체
- 대체된 개별 구현 파일 삭제
- 전체 동작 검증

---

## 6-1. 삭제 대상 파일/코드

### 파일 삭제 검토

| 파일 | 대체 컴포넌트 | 삭제 조건 |
|------|-------------|----------|
| `RecentSearchCell.swift` | DrawerListCell | HomeDrawer에서 미사용 확인 후 |
| `SearchResultCell.swift` | DrawerListCell | SearchResultDrawer에서 미사용 확인 후 |
| `HomeSectionHeaderView` (HomeDrawerVC 하단) | DrawerSectionHeaderView | 인라인 코드이므로 해당 클래스만 삭제 |

### 코드 삭제

- HomeVC: searchBarContainer 관련 코드 전체 (Phase 3에서 처리)
- 각 드로어: 개별 titleLabel, closeButton, titleSeparator 선언/레이아웃 (Phase 4에서 처리)

---

## 6-2. 매직넘버 전수 검사

### 검색 패턴

프로젝트 전체에서 아래 패턴으로 검색하여 남은 매직넘버를 확인한다:

```
// 하드코딩 수치 검색
equalToConstant: [0-9]
pointSize: [0-9]
ofSize: [0-9]
withAlphaComponent(0.
cornerRadius = [0-9]
width: [0-9], height: [0-9]
CGFloat = [0-9]
```

### 예외 (토큰화 불필요)

- `0` (zero) 제약조건
- `1 / UIScreen.main.scale` (픽셀 단위 구분선)
- `UICollectionView` 섹션 인덱스 (0, 1)
- CarPlay 전용 값 (CPMapTemplate 등 외부 프레임워크 의존)
- 애니메이션 duration (0.3, 0.25 등)
- 물리 상수 (속도 13.9 m/s 등)

---

## 6-3. 전체 동작 검증

### 홈 화면 플로우

- [ ] 앱 실행 -> 홈 화면 표시
- [ ] 홈드로어에 검색바 + 설정 버튼 표시
- [ ] 검색바 탭 -> 드로어 full 전환 -> SearchVC 모달
- [ ] 검색 완료 -> SearchVC 닫힘 -> SearchResultDrawer 표시 -> 드로어 medium 복귀
- [ ] 검색 취소 -> SearchVC 닫힘 -> 드로어 medium 복귀
- [ ] 설정 버튼 탭 -> SettingsVC 표시

### 드로어 헤더 통일

- [ ] HomeDrawer: 검색바 + 설정 + separator
- [ ] SearchResultDrawer: "검색 결과" 중앙 + 닫기 + separator
- [ ] POIDetail: 아이콘 + 장소명 + 즐겨찾기 + 닫기 + separator
- [ ] RoutePreview: 목적지명 + 즐겨찾기 + 닫기 + separator

### 드로어 인터랙션

- [ ] 헤더 영역 드래그 -> 드로어 이동
- [ ] 콘텐츠 영역 스크롤 -> 콘텐츠 스크롤
- [ ] small / medium / large detent 스냅 정상
- [ ] 드로어 push / pop / replace 애니메이션 정상

### 각 드로어 기능

- [ ] HomeDrawer: 즐겨찾기 탭 -> POIDetail
- [ ] HomeDrawer: 최근 검색 탭 -> 동작
- [ ] HomeDrawer: 즐겨찾기 롱프레스 -> 편집/삭제 메뉴
- [ ] SearchResultDrawer: 결과 항목 탭 -> POIDetail
- [ ] SearchResultDrawer: 스크롤 -> 지도 포커스 변경
- [ ] SearchResultDrawer: 닫기 -> 홈 복귀
- [ ] POIDetail: 경로 버튼 -> RoutePreview
- [ ] POIDetail: 즐겨찾기 토글 (신규)
- [ ] POIDetail: 닫기 -> 이전 드로어
- [ ] RoutePreview: 이동수단 전환 -> 경로 재탐색
- [ ] RoutePreview: 경로 선택 -> 지도 반영
- [ ] RoutePreview: 안내 시작 -> 주행 화면
- [ ] RoutePreview: 가상 주행 -> 시뮬레이션
- [ ] RoutePreview: 즐겨찾기 토글
- [ ] RoutePreview: 닫기 -> 홈 복귀

### 주행/설정/재생

- [ ] 주행 화면: 매뉴버 배너 표시 정상
- [ ] 주행 화면: 하단바 ETA/거리/시간 표시 정상
- [ ] 주행 화면: 안내 종료 -> 홈 복귀
- [ ] 주행 화면: 재센터 버튼 동작
- [ ] 가상 주행: 재생 컨트롤 표시 정상
- [ ] 가상 주행: 재생/일시정지/정지/배속 동작
- [ ] 설정 화면: 모든 셀 표시 정상
- [ ] 설정 화면: 토글/선택 동작
- [ ] 개발자도구: 모든 셀 표시 정상

### 레이아웃 검증

- [ ] safeArea 처리 정상 (노치/다이나믹 아일랜드)
- [ ] 다크모드 전환 시 색상 정상
- [ ] 가로모드 (지원 시) 레이아웃 정상
- [ ] 다양한 기기 크기 (SE ~ Pro Max) 레이아웃 정상

---

## 6-4. 최종 파일 구조

### 신규 파일

```
Common/UI/DesignSystem/
├── Theme+Drawer.swift
├── Theme+Component.swift
├── DrawerHeaderView.swift
├── DrawerSectionHeaderView.swift
├── DrawerListCell.swift
├── DrawerActionButton.swift
├── DrawerIconButton.swift
├── DrawerSeparator.swift
├── SearchBarView.swift
└── OverlayContainer.swift
```

### 수정 파일

```
Common/UI/Theme.swift                              (IconSize 추가, overlay 색상 추가)
Feature/Home/HomeViewController.swift               (검색바/설정 제거, detent 변경)
Feature/Home/HomeDrawerViewController.swift          (헤더 추가, 셀/헤더 교체)
Feature/Search/SearchResultDrawerViewController.swift (공통 컴포넌트 적용)
Feature/POIDetail/POIDetailViewController.swift       (공통 컴포넌트 적용)
Feature/RoutePreview/RoutePreviewDrawerViewController.swift (공통 컴포넌트 적용)
Feature/RoutePreview/RouteOptionCell.swift             (토큰 적용)
Feature/Navigation/NavigationViewController.swift      (토큰 적용)
Feature/Navigation/PlaybackControlView.swift           (토큰 적용)
Feature/Settings/SettingsViewController.swift          (토큰 적용)
Feature/DevTools/DevToolsViewController.swift          (토큰 적용)
Feature/Home/MapControlButtonsView.swift               (토큰 적용)
Coordinator/AppCoordinator.swift                       (검색 플로우, detent 변경)
```

### 삭제 파일 (검토 후)

```
Feature/Home/RecentSearchCell.swift           (DrawerListCell로 대체)
Feature/Search/SearchResultCell.swift         (DrawerListCell로 대체)
Feature/Home/HomeSectionHeaderView (인라인)    (DrawerSectionHeaderView로 대체)
```
