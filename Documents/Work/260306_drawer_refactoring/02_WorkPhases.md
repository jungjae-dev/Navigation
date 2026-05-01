# Drawer Refactoring - 작업 단계

## 작업 순서 개요

```
Phase 1: DrawerContainerManager 기반 인프라 구축
Phase 2: HomeDrawer를 child VC로 전환
Phase 3: SearchResult/RoutePreview를 Primary 교체로 전환
Phase 4: POIDetail을 Overlay slot으로 전환
Phase 5: AppCoordinator 정리 및 레거시 제거
Phase 6: 검증 및 엣지 케이스 처리
```

---

## Phase 1: DrawerContainerManager 기반 인프라 구축

### 목표
DrawerContainerManager, DrawerDetent, DrawerContainerView, GrabberView 신규 파일 생성.
이 단계에서는 아직 기존 코드에 연결하지 않음.

### 작업 항목

1. **DrawerDetent.swift** 생성
   - `DrawerDetent` 구조체 (identifier, height)
   - `absolute`, `fractional` 팩토리 메서드

2. **GrabberView.swift** 생성
   - 48x5pt 둥근 바 (시스템 grabber와 유사)
   - 상단 중앙 배치

3. **DrawerContainerView.swift** 생성
   - `hitTest` 오버라이드로 터치 패스쓰루
   - cornerRadius (상단 좌우 12pt)
   - 그림자 (shadow)

4. **DrawerContainerManager.swift** 생성
   - primaryContainerView + overlayContainerView 관리
   - UIPanGestureRecognizer + detent snap 로직
   - slide up / slide down 애니메이션
   - `setPrimary()`, `showOverlay()`, `hideOverlay()`
   - `hideAll()`, `showPrimary()`
   - `onHeightChanged` 콜백
   - spring animation (damping: 0.8, response: 0.3)
   - rubber band 효과 (최소/최대 detent 초과 시)

### 완료 기준
- DrawerContainerManager를 빈 UIViewController에 붙여서 독립 테스트 가능
- pan gesture로 detent 전환 동작 확인
- slide up/down 애니메이션 동작 확인
- 빌드 성공

### 영향 범위
- 기존 코드 변경 없음 (신규 파일만 추가)

---

## Phase 2: HomeDrawer를 child VC로 전환

### 목표
HomeDrawerViewController를 modal present 대신 DrawerContainerManager의 Primary slot에 child VC로 배치.
AppCoordinator의 `presentHomeDrawer()` / `dismissHomeDrawer()` 를 DrawerContainerManager 호출로 교체.

### 작업 항목

1. **HomeViewController 수정**
   - DrawerContainerManager 인스턴스 소유
   - `setupDrawerContainer()` — containerView를 view에 addSubview
   - bottom constraint 설정 (safeArea 기준)

2. **AppCoordinator 수정**
   - `presentHomeDrawer()` -> `drawerManager.setPrimary(.home, ...)`
   - `dismissHomeDrawer()` -> `drawerManager.hideAll()`
   - `UINavigationControllerDelegate` 홈드로어 복원 -> `drawerManager.showPrimary()`
   - map inset 콜백을 `onHeightChanged`로 통합

3. **HomeDrawerViewController 수정**
   - `isModalInPresentation = true` 제거
   - `scrollViewWillEndDragging` 에서 DrawerScrollHelper 호출 제거
     (pan gesture가 DrawerContainerManager에서 처리)

### 완료 기준
- 앱 시작 시 HomeDrawer가 child VC로 표시됨
- 3단계 detent 드래그 동작
- 지도 터치 패스쓰루 정상
- 지도 컨트롤 버튼 detent 연동
- 설정 진입/복귀 시 hide/show 정상
- 빌드 성공

### 영향 범위
- HomeViewController.swift
- AppCoordinator.swift (presentHomeDrawer, dismissHomeDrawer, navigationDelegate 부분)
- HomeDrawerViewController.swift

### 주의사항
- 이 단계에서는 SearchResult, RoutePreview, POIDetail은 여전히 기존 modal sheet 방식 유지
- homeDrawer가 child VC가 되면서, 기존에 homeDrawer 위에 present 하던 코드는 presenter를 navigationController로 변경해야 함

---

## Phase 3: SearchResult/RoutePreview를 Primary 교체로 전환

### 목표
SearchResultDrawerViewController와 RoutePreviewDrawerViewController를 modal present 대신
DrawerContainerManager의 `setPrimary()`로 교체.

### 작업 항목

1. **AppCoordinator - showSearchResults() 수정**
   - `homeDrawer.present(drawerVC)` + `asyncAfter(0.35)` 제거
   - `drawerManager.setPrimary(.searchResult, ...)` 호출
   - 교체 애니메이션: Home slide down -> SearchResult slide up

2. **AppCoordinator - presentRoutePreviewDrawer() 수정**
   - `homeDrawer.present(drawerVC)` + `asyncAfter(0.35)` 제거
   - `drawerManager.setPrimary(.routePreview, ...)` 호출

3. **AppCoordinator - 닫기 처리 수정**
   - `dismissSearchResultDrawerWithCleanup()` -> `drawerManager.setPrimary(.home, ...)`
   - `dismissRoutePreviewDrawerWithCleanup()` -> `drawerManager.setPrimary(.home, ...)`
   - `dismissIntermediateDrawers()` -> `drawerManager.hideOverlay()` + `setPrimary()`

4. **AppCoordinator - dismissAllDrawers() 수정**
   - `navigationController.dismiss()` -> `drawerManager.hideAll()`

5. **SearchResultDrawerViewController 수정**
   - sheet 관련 코드 제거
   - `scrollViewWillEndDragging` DrawerScrollHelper 호출 제거

6. **RoutePreviewDrawerViewController 수정**
   - sheet 관련 코드 제거

7. **SearchViewController present 방식 변경**
   - presenter를 `homeDrawer ?? navigationController` 에서 `navigationController`로 통일
   - 검색 진입 시 `drawerManager.hideAll()` -> present SearchVC
   - 검색 복귀 시 dismiss SearchVC -> `drawerManager.showPrimary()`

### 완료 기준
- 검색 결과 선택 시 SearchResult가 slide up으로 표시 (asyncAfter 없음)
- SearchResult 닫기 시 Home으로 교체 전환 (slide down -> slide up)
- 경로 탭 시 RoutePreview로 교체 전환
- RoutePreview 닫기 시 Home으로 복귀
- 안내 시작 시 모든 드로어 hideAll -> push
- 빌드 성공

### 영향 범위
- AppCoordinator.swift (showSearchResults, presentRoutePreviewDrawer, dismiss 함수들, showSearch)
- SearchResultDrawerViewController.swift
- RoutePreviewDrawerViewController.swift

### 주의사항
- POIDetail은 아직 modal sheet 방식 유지 (Phase 4에서 전환)
- 이 단계에서 `asyncAfter(0.35)` 2곳 모두 제거됨

---

## Phase 4: POIDetail을 Overlay slot으로 전환

### 목표
POIDetailViewController를 modal present 대신 DrawerContainerManager의 Overlay slot으로 전환.

### 작업 항목

1. **AppCoordinator - showPOIDetail / showPOIDetailFromDrawer 수정**
   - `presenter.present(detailVC)` -> `drawerManager.showOverlay(detailVC, height: 320)`
   - 기존 POI가 있으면 `drawerManager.updateOverlay(with: place)`

2. **AppCoordinator - dismissPOIDetailWithCleanup() 수정**
   - `poiDetailDrawer?.dismiss()` -> `drawerManager.hideOverlay()`

3. **AppCoordinator - 경로 탭 복합 전환 수정 (D -> E)**
   - `drawerManager.hideOverlay(animated: false)`
   - `drawerManager.setPrimary(.routePreview, ...)` (기존 Primary도 교체)
   - 애니메이션: POI + SearchResult 동시 slide down -> RoutePreview slide up

4. **POIDetailViewController 수정**
   - sheet detent 설정 코드 제거

5. **UISheetPresentationControllerDelegate 제거**
   - `sheetPresentationControllerDidChangeSelectedDetentIdentifier` 제거
   - `presentationControllerDidDismiss` 제거
   - 모든 detent/dismiss 처리가 DrawerContainerManager로 이관됨

### 완료 기준
- 지도 POI 탭 시 Overlay로 POI 표시 (slide up)
- POI 닫기 시 Overlay slide down (Primary 이미 보임)
- SearchResult + POI 상태에서 경로 탭 시 복합 전환 동작
- POI가 이미 열려있을 때 다른 POI 탭 시 내용만 update
- presentationControllerDidDismiss 완전 제거
- 빌드 성공

### 영향 범위
- AppCoordinator.swift (showPOIDetail, dismissPOIDetail, presentPOIDetail, delegate 제거)
- POIDetailViewController.swift

---

## Phase 5: AppCoordinator 정리 및 레거시 제거

### 목표
Phase 2~4에서 남겨둔 레거시 코드, 미사용 프로퍼티, 불필요한 import 정리.

### 작업 항목

1. **제거 대상 프로퍼티**
   - `homeDrawer: HomeDrawerViewController?` -> DrawerContainerManager가 관리
   - `currentDrawer: SearchResultDrawerViewController?` -> DrawerContainerManager가 관리
   - `poiDetailDrawer: POIDetailViewController?` -> DrawerContainerManager가 관리
   - `routePreviewDrawer: RoutePreviewDrawerViewController?` -> DrawerContainerManager가 관리

2. **제거 대상 메서드**
   - `presentHomeDrawer()`
   - `dismissHomeDrawer()`
   - `dismissAllDrawers()`
   - `dismissIntermediateDrawers()`
   - `dismissSearchResultDrawerWithCleanup()`
   - `dismissPOIDetailWithCleanup()`
   - `dismissRoutePreviewDrawerWithCleanup()`
   - `configureSheetDetents(for:)`
   - `drawerHeight(for:in:)`

3. **제거 대상 extension**
   - `UISheetPresentationControllerDelegate` extension 전체

4. **DrawerScrollHelper.swift**
   - 파일 삭제 (DrawerContainerManager의 pan gesture가 대체)

5. **코드 정리**
   - 미사용 import 제거
   - 주석 정리
   - AppCoordinator `NSObject` 상속 필요 여부 확인 (sheet delegate 제거 후)

### 완료 기준
- 컴파일 경고 없음
- 미사용 코드/프로퍼티 없음
- 빌드 성공
- 모든 시나리오 정상 동작

### 영향 범위
- AppCoordinator.swift
- DrawerScrollHelper.swift (삭제)

---

## Phase 6: 검증 및 엣지 케이스 처리

### 목표
33개 시나리오 전수 검증 + 엣지 케이스 처리.

### 작업 항목

1. **33개 시나리오 전수 검증** (01_DesignDoc.md 4장 기준)

2. **엣지 케이스 검증**
   - 빠른 연속 탭 (닫기 -> 즉시 다른 액션)
   - 드래그 중 닫기 버튼 탭
   - 검색 결과 0개 상태
   - 즐겨찾기/최근검색 0개 상태
   - CarPlay 동시 사용 시나리오
   - 회전/멀티태스킹 (iPad 미지원이면 생략)
   - 메모리 경고 시 드로어 상태 유지

3. **애니메이션 품질 확인**
   - slide up/down 속도 적절한지
   - 겹침 전환 타이밍 자연스러운지
   - rubber band 느낌 적절한지
   - 접근성 설정 (Reduce Motion) 대응

4. **빌드 및 테스트**
   ```bash
   xcodebuild build \
     -scheme Navigation \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -quiet

   xcodebuild test \
     -scheme Navigation \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -quiet
   ```

### 완료 기준
- 33개 시나리오 전수 통과
- 엣지 케이스 처리 완료
- 빌드 + 테스트 통과
- 접근성 대응 확인

---

## 단계별 의존성

```
Phase 1 (인프라)
  |
  v
Phase 2 (HomeDrawer child VC)
  |
  v
Phase 3 (SearchResult/RoutePreview 교체)
  |
  v
Phase 4 (POIDetail overlay)
  |
  v
Phase 5 (레거시 정리)
  |
  v
Phase 6 (검증)
```

각 Phase는 이전 Phase 완료 후 진행. Phase 간 빌드 성공을 보장하여 언제든 중단/재개 가능.
