# 요구사항 — 도보 모드 정리 (차량 껍데기 → 도보)

제품 방향: **도보 메인** (자전거는 나중에 보조). 차량 내비는 Drop.
성격: **순수 리팩토링** — 길안내 엔진·기능은 **그대로 두고**, 차량 전용 "껍데기"만 도보용으로 교체. + 신규 1개(진행률 progress).
근거 스캔: 2026-06-21 실제 코드 기준(추정 아님).

---

## 1. 핵심 원칙
> **"엔진은 그대로, 자동차 운전석을 떼고 도보용 표면으로 교체."**
> 맵매칭·재탐색·턴바이턴 로직·음성·주행화면 구조는 **유지**. 차량 전용 모드·UI·CarPlay만 제거/도보화.

## 2. 유지 (건드리지 않음 — 회귀 방지 핵심)
- 길안내 엔진: `Engine/NavigationEngine`·`RouteTracker`·`OffRouteDetector`·맵매칭·재탐색
- 음성 엔진(`VoiceEngine`) — 문구만 다듬되 로직 유지
- 주행화면(`Feature/Navigation/NavigationViewController`)과 회전 배너·도착팝업·재중심·GPS상태·재탐색배너
- **도보 경로는 이미 됨**: `TransportMode`에 `.walking` 존재 → 도보 내비 기능을 새로 만들 필요 없음

## 3. 제거 / 차단 (차량 껍데기)

### 3-A. 완전 제거
| 대상 | 위치 | 처리 |
|---|---|---|
| **CarPlay 전체** | `App/CarPlaySceneDelegate.swift`, `Feature/CarPlay/`(SearchHandler·MapViewController·NavigationHandler·FavoritesHandler), `Service/CarPlay/NavigationSessionManager.swift` | 파일·씬·Info.plist(CarPlay 씬/역할) 제거 |
| **속도계** | `Feature/Navigation/View/SpeedometerView.swift` + `NavigationViewController.speedometerHostingController` | 제거 (도보 속도 무의미) |

### 3-B. 입구 차단 (차량 경로 — 코드는 죽은 채 유지, 삭제 안 함)
`.automobile`로 흐름이 들어가는 **입구 3곳만** 막아 차량 경로 분기를 비활성화. `KakaoRouteService`의 `case .automobile`(→`calculateDrivingRoutes`)·Apple 차량 분기·`TransportMode.automobile` enum은 **삭제하지 않음**(미사용 죽은 코드 → 정리는 Later/선택).

| # | 입구 | 위치 | 조치 |
|---|---|---|---|
| 1 | 이동수단 선택 세그먼트(자동차/도보) | `Feature/RoutePreview/RoutePreviewDrawerViewController` (`transportModeSegment`) | **세그먼트 제거 → 도보 단일** |
| 2 | 경로 미리보기 기본 모드 | `AppCoordinator.presentRoutePreviewDrawer(... transportMode: = .automobile)` | 기본값 **`.walking`** |
| 3 | ETA 계산 하드코딩 | `KakaoRouteService.calculateETA(...)` (`transportMode: .automobile`) | **`.walking`** |

> 결과: 세 입구를 도보로 돌리면 차량 라우팅 코드는 **호출 안 됨**. 굳이 삭제하지 않아 리팩토링이 작고 안전.
> 참고: 통행료·고속도로 옵션은 **코드에 없음**(스캔 0건).

## 4. 도보화 (다듬기 — 표면만)
| 요소 | 위치 | 변경 |
|---|---|---|
| **회전 안내 거리** | `Feature/Navigation/View/ManeuverBannerView` + 안내 트리거 | **도보 기준 거리 임계값**(예: 50m 예고 → 20m → 10m "지금 우회전") + 도보 문구("횡단보도 건너기" 등) |
| **하단바 ETA** | `Feature/Navigation/View/NavigationBottomBar` | ETA를 **도보 속도** 기준으로 |
| **지도 카메라** | `Map/MapViewController.configureForNavigation` | **heading-up 유지**(맵매칭 course라 안정적) + 틸트↓·줌↑(street-level) 미세 조정 |
| 음성 문구 | `VoiceEngine` | 차량 표현 제거, 도보 맥락 문구 |

## 5. 신규 (이번 추가 기능)
- **하단바 진행률 progress**: 전체 경로 거리 중 **현재까지 진행한 거리**를 progress(막대/비율)로 표시.
  - 위치: `NavigationBottomBar` (ETA·남은거리 옆/위)
  - 데이터: 엔진의 전체 경로 거리 + 진행 거리(맵매칭 위치 기준) → **확인 필요**(엔진이 노출하는지, 9절)

## 6. 차량 아이콘 — 현행 유지 (결정)
- `Service/VehicleIcon/*` 및 주행 중 아이콘 표시는 **이번엔 그대로 둠**.
- 도보 표시(사람/방향 화살표)로 교체는 **Later**.

## 7. 기능 요구사항 (FR)
- **FR-1**: 모든 경로 호출 이동수단을 **도보(`.walking`)로** — ① RoutePreview 세그먼트 제거 ② `presentRoutePreviewDrawer` 기본값 `.walking` ③ `calculateETA` `.walking`(입구 3곳). `TransportMode.automobile` enum·차량 라우팅 코드는 **유지(미사용 죽은 코드)**.
- **FR-2**: 차량 라우팅 코드(`calculateDrivingRoutes`·`case .automobile`)는 **삭제하지 않음** — FR-1로 호출만 차단됨. (정리는 Later/선택)
- **FR-3**: CarPlay 모듈·씬·Info.plist 제거.
- **FR-4**: 속도계 제거(SpeedometerView + 호스팅).
- **FR-5**: 회전 안내를 **도보 거리 임계값 + 도보 문구**로.
- **FR-6**: 하단바 ETA를 도보 속도 기준으로.
- **FR-7**: 카메라 heading-up 유지 + 틸트↓·줌↑ 도보 튜닝.
- **FR-8**: **(신규) 하단바 진행률 progress** — 전체 거리 대비 진행 거리.
- **FR-9**: 차량 아이콘은 **현행 유지**(도보화는 Later).
- **FR-10**: 제거로 생긴 죽은 코드/참조/리소스 정리, 차량 시나리오 테스트 정리.
- **FR-11**: 경로 미리보기 진입 시 **POI 레이어 마커(버스 정류소·따릉이) 임시 숨김**, 미리보기 종료 시 **복원**. 레이어 토글 상태(`isLayerOn`)는 유지(시각적으로만 임시 숨김). 입구: `AppCoordinator.presentRoutePreviewDrawer`→`clearBusStops()`/`clearBikeStations()`, `dismissRoutePreviewDrawerWithCleanup`→레이어 on이면 재표시.

## 8. 비목표 / Later
- 자전거 보조 모드(도보경로+자전거 ETA) — Later (TransportMode에 bike 추가는 별건)
- 차량 아이콘 → 도보 표시 교체 — Later
- 무장애(계단 회피) 경로, 도보 AR — Later
- 음성 문구 정밀 도보화(고도화) — 기본만 이번, 정밀은 Later

## 9. 확인 필요 (plan/스파이크)
1. **엔진이 "전체 경로 거리 + 진행 거리"를 노출하는지** (`NavigationEngine`/`RouteTracker`) → 진행률 progress(FR-8) 가능 여부. 없으면 진행거리 계산 추가.
2. 도보 회전 안내 거리 임계값 구체값(50/20/10m 등) 확정.
3. `.automobile` 참조 전체 범위(컴파일 영향) — plan에서 코드 스캔.
4. CarPlay 제거 시 씬/Info.plist/타깃 설정 영향 범위.

## 10. 영향 파일 (실제 스캔 기준)
| 영역 | 파일 | 변경 |
|---|---|---|
| 이동수단 enum | `Service/Route/RouteModels.swift` | `.automobile` **유지**(미사용 죽은 코드) |
| 경로 서비스 | `Service/LBS/Kakao/KakaoRouteService`·`Apple/AppleRouteService`·`Fallback/` | 차량 분기 **유지**(죽은 코드). `calculateETA` 하드코딩만 `.walking`으로 |
| 경로 선택 | `Feature/RoutePreview/RoutePreviewDrawerViewController` | **이동수단 세그먼트 제거**(도보 단일) |
| CarPlay | `App/CarPlaySceneDelegate.swift`·`Feature/CarPlay/*`·`Service/CarPlay/*` | **제거** + 씬/Info.plist |
| 주행화면 | `Feature/Navigation/NavigationViewController.swift` | 속도계 호스팅 제거, progress 추가 배선 |
| 속도계 | `Feature/Navigation/View/SpeedometerView.swift` | 제거 |
| 회전 배너 | `Feature/Navigation/View/ManeuverBannerView.swift` | 도보 거리/문구 |
| 하단바 | `Feature/Navigation/View/NavigationBottomBar.swift` | 도보 ETA + **진행률 progress 신규** |
| 카메라 | `Map/MapViewController.swift` (`configureForNavigation`) | heading-up 유지, 틸트↓·줌↑ |
| 음성 | `Engine/VoiceEngine`(또는 `Voice/`) | 도보 문구 |
| 엔진 | `Engine/NavigationEngine`·`RouteTracker` | (필요시) 진행 거리 노출만 — 차량 분기 안 건드림 |
| 조정자 | `Coordinator/AppCoordinator` | `presentRoutePreviewDrawer` 기본값 `.walking` |
| 차량 아이콘 | `Service/VehicleIcon/*` | **유지**(Later) |

## 11. 성격 / 주의
- **신규 화면·진입점 없음** (주행화면 내부 변경 + 차량 자산 제거).
- 진행률 progress 외엔 기능 추가 없음 — 나머지는 제거/도보 튜닝.
- **회귀 방지 최우선**: 도보 길안내(맵매칭·재탐색·음성·턴바이턴) 동작 보존. 차량 테스트 정리, 도보 테스트 보강(Swift Testing).
- 002 디자인: 주행화면은 002 out-of-scope. 단 신규 progress UI는 Theme 토큰 사용.
</content>
