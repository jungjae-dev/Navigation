# Implementation Plan: 실시간 도시 혼잡 지도 (Live City Pulse)

**Branch**: `004-live-congestion` | **Date**: 2026-06-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-live-congestion/spec.md`

## Summary

홈 지도에 **실시간 혼잡 마커 레이어 + 지금→+12h 예측 슬라이더** 모드를 얹는다. 서울 실시간 도시데이터(`citydata_ppltn`)가 혼잡 단계·예측을 직접 제공 → 앱은 **보이는 영역의 핫스팟만** 받아(뷰포트 로딩 + TTL 캐시) 단계색 마커로 표시. 자체 전처리·예측모델 없음. MVP = 실시간 마커 + 예측 슬라이더 + 장소 상세 곡선 + 신선도/복원. 면 색칠·자동재생은 Later.

**기술 접근(리서치 확정)**:
- **API**: `citydata_ppltn`(경량) — 기존 `SeoulAPIClient` 재사용(동일 호스트·키). 장소별 호출.
- **좌표**: 응답에 좌표 없을 가능성 → ~120 핫스팟 (장소명→좌표) **번들 매핑**(소량 정적).
- **로딩**: `onRegionChanged`(L460)/`regionDidChange`(L868) 구독 → **보이는 영역 핫스팟만 병렬 호출 + TTL 캐시**(타임아웃·부분실패 허용).
- **표시**: bike/bus 어노테이션 패턴으로 **혼잡 단계색 마커**. 슬라이더 offset → 색만 갱신.
- **상세**: `showMapItemDetail(content:)`(L510) 재사용 — `CongestionContent: MapItemContent`(예측 곡선).
- **진입/종료**: `pushDrawer/popDrawer` + 따릉이·버스 레이어 배타 OFF/복원.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency, MainActor 격리).

**Primary Dependencies**: UIKit(programmatic), MapKit(`MKAnnotationView`), Combine, SwiftUI(드로어/곡선), `SeoulAPIClient`(기존), Swift Testing.

**Storage**: 런타임 TTL 캐시(장소별, 비영속) + 번들 HotspotCatalog. 영속 SwiftData 없음.

**Testing**: Swift Testing — 혼잡 파싱·offset 선택·가시영역 필터 단위 + 시뮬레이터 로그.

**Target Platform**: iOS 26 (`iPhone 17 Pro`).

**Project Type**: Mobile app (단일 iOS 타깃, MVVM + Coordinator + Combine).

**Performance Goals**: offset 변경 색 갱신 0.3s(SC-002, 이미 받은 예측); 가시 영역 호출 보통 <20곳; 부분실패 허용.

**Constraints**: 서울 공공데이터만(FR-014); 라이브(네트워크 필요, 캐시·기준시각 노출); 신규 화면 없음; 커버리지 ~120곳 한계 정직 노출.

**Scale/Scope**: 핫스팟 ~120(번들). 신규 ~6 파일(Feature/LivePulse, Service/LivePulse, 혼잡 마커) + 진입/코디네이터 배선.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 원칙 | 평가 | 비고 |
|---|---|---|
| I. Swift 6 Concurrency | ✅ PASS | async 호출, MainActor UI. 신규 delegate 없음 |
| II. MVVM + Coordinator + Combine | ✅ PASS | `LivePulseViewModel`=`CurrentValueSubject`, 전환=`AppCoordinator.showLivePulse/exitLivePulse`. `@Published` 미사용 |
| III. 단순성 우선(YAGNI) | ✅ PASS | MVP=마커+슬라이더+상세. 면·자동재생·결합은 Later(선반영 안 함) |
| IV. 로그 기반 검증 | ✅ PASS | quickstart S1~S7 로그(`[LivePulse]`) + 파싱/offset 단위 테스트 |
| V. iOS 26 / Xcode 26 | ✅ PASS | MapKit 어노테이션 표준. 시뮬레이터 iPhone 17 Pro |
| Arch. POI 레이어 통합 | ✅ PASS | 혼잡은 따릉이/버스와 배타(진입 OFF) — 통합 관리 원칙 정합 |
| Arch. API 키 | ✅ PASS | `Secrets.xcconfig` SEOUL_OPEN_API_KEY 재사용, 커밋 금지 |

**결과**: PASS. 위반 없음 → Complexity Tracking 불필요.

## Project Structure

### Documentation (this feature)

```text
specs/004-live-congestion/
├── plan.md           # 본 파일
├── research.md       # Phase 0 — API·좌표·뷰포트·마커·슬라이더·상세·진입 결정
├── data-model.md     # Phase 1 — CongestionPlace·Forecast·Level·Catalog·TimelineState·캐시
├── quickstart.md     # Phase 1 — 시뮬레이터 검증 시나리오
├── contracts/
│   └── live-pulse-ui.md
└── tasks.md          # /speckit-tasks 산출 (본 명령 아님)
```

### Source Code (repository root)

```text
Navigation/Navigation/
├── Feature/LivePulse/                      # [신규]
│   ├── LivePulseDrawerViewController.swift   # 시간 슬라이더 + 기준시각 + 새로고침
│   ├── LivePulseViewModel.swift              # CurrentValueSubject<TimelineState> + places + offset→level
│   ├── CongestionLevel.swift                 # 단계 enum + 파싱 + 색 (순수, 테스트 대상)
│   └── CongestionContent.swift               # MapItemContent — 상세 예측 곡선
├── Service/LivePulse/                      # [신규]
│   ├── CitydataService.swift                 # citydata_ppltn 병렬 호출 + TTL 캐시 (SeoulAPIClient 재사용)
│   ├── CitydataModels.swift                  # 응답 디코딩 (AREA_CONGEST_LVL/FCST_PPLTN…)
│   └── HotspotCatalog.swift                  # 번들 장소명→좌표 로드
├── Resources/hotspots.json                 # [신규] ~120 핫스팟 좌표 매핑(번들)
├── Map/
│   ├── MapViewController.swift               # setCongestion/clearCongestion/updateCongestionColors + onRegionChanged 구독
│   └── Congestion/CongestionAnnotation(+View).swift  # [신규] 단계색 마커 (bike/bus 패턴)
├── Feature/Home/MapControlButtonsView.swift # onLivePulseTapped 버튼
├── Feature/Home/HomeViewController.swift     # 진입/종료 레이어 저장·복원 배선
└── Coordinator/AppCoordinator.swift          # showLivePulse/exitLivePulse + 마커 탭→상세

NavigationTests/CongestionLevelTests.swift   # [신규] 파싱·offset·가시영역 단위
```

**Structure Decision**: 기존 단일 iOS 타깃 + 패턴(서울 OpenAPI 클라이언트·TTL 캐시·어노테이션·드로어 스왑·레이어 토글·상세 팝업) 재사용. 신규 모듈 없음. 라이브 데이터라 전처리 산출물·스크립트 불필요(시간여행 대비 단순).

## Complexity Tracking

> 위반 없음 — 비움.
