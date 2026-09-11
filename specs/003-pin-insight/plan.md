# Implementation Plan: 핀 기반 동네 인사이트

**Branch**: `003-pin-insight` | **Date**: 2026-06-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-pin-insight/spec.md`
**Detailed requirements**: `Documents/Work/260619_1_pin_insight/requirements.md` (데이터셋·통합 설계·API 검증)

## Summary

지도 롱프레스로 찍은 핀 좌표의 동네 생활 환경(활기·대기질·교통·편의·녹지·안전·행사)을 서울 공공데이터로 종합해 **기존 POI 상세 팝업(`MapItemDetailViewController`)에 카드로 표시**한다. 신규 화면 0개 — `MapItemContent` 프로토콜에 `PinInsightContent`를 추가하고, 점→행정동 변환(Kakao `coord2regioncode`)과 반경/구역 질의를 `NeighborhoodInsightService`가 병렬 집계한다. 카드별 독립 로딩으로 부분 실패를 격리하고, 실시간 값(따릉이·대기질)에는 기준 시각('○분 전')을 표시한다.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
**Primary Dependencies**: UIKit(programmatic), MapKit, Combine, SwiftData, Kakao REST(coord2regioncode), 서울 열린데이터광장 OpenAPI
**Storage**: SwiftData(관심 동네) / 정적 데이터 파일 캐시(`Documents/`, 공중화장실 등) / in-memory 캐시(실시간·준정적)
**Testing**: Swift Testing (`import Testing`, `#expect`, `@Test`)
**Target Platform**: iOS 26 (시뮬레이터 `iPhone 17 Pro`)
**Project Type**: mobile-app (iOS, 단일 앱)
**Performance Goals**: 첫 카드 <1.5s, 전체 카드 <3s(병렬), 시트 애니메이션 60fps
**Constraints**: 서울 공공데이터만 사용 / 무료+비침습 광고 / 좌표계(TM·GRS80→WGS84) 변환 / 카드별 graceful 실패 / 공공누리 4유형(둘레길·방범CCTV) 미사용
**Scale/Scope**: 서울 ~424 행정동·25 자치구, 단일 사용자 앱, 카드 7종

## Constitution Check

*GATE: Phase 0 전 통과, Phase 1 후 재검토.*

| 원칙 | 준수 | 근거 |
|---|---|---|
| I. Swift 6 Concurrency | ✅ | MainActor 격리; delegate는 `nonisolated`+`MainActor.assumeIsolated`; API는 async/await + `TaskGroup` |
| II. MVVM+Coordinator+Combine | ✅ | `InsightViewModel`이 `CurrentValueSubject`로 카드 상태 노출; `AppCoordinator`가 진입(`showNeighborhoodInsight`); `@Published` 미사용 |
| III. 단순성(YAGNI) | ✅ | 비목표(비교·종합점수·소음) 제외; 카드 7종만; 카드별 실제 발생 에러만 처리 |
| IV. 로그 기반 검증 | ✅ | 핀 드롭→행정동 식별→카드별 fetch 결과를 Logger 포인트로 검증(quickstart) |
| V. iOS 26 API | ✅ | `MKMapItem(location:address:)`, `mapItem.location.coordinate` 사용 |
| AC. 지도 POI=POI 팝업 통합 | ✅ | `PinInsightContent`로 기존 `MapItemDetailViewController` 재사용(따릉이·버스와 동일) |
| AC. API 키 Secrets.xcconfig | ✅ | Kakao·서울 인증키는 `Secrets.xcconfig`(커밋 금지) |
| AC. 정적 데이터 캐시 | ✅ | 공중화장실 등 OpenAPI 없는 파일은 `Documents/` 캐시 + 번들 fallback |

**위반 없음** → Complexity Tracking 비움.

## Project Structure

### Documentation (this feature)

```text
specs/003-pin-insight/
├── plan.md              # 이 파일
├── research.md          # Phase 0 (데이터·기술 결정)
├── data-model.md        # Phase 1 (엔티티)
├── quickstart.md        # Phase 1 (빌드·검증)
├── contracts/
│   └── seoul-apis.md    # Phase 1 (소비하는 외부 API 계약)
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root: `Navigation/Navigation/Navigation/`)

```text
Feature/
├── MapItemDetail/Content/
│   └── PinInsightContent.swift            # 신규: MapItemContent 구현(헤더+카드+푸터)
├── Insight/                               # 신규 모듈
│   ├── InsightViewModel.swift             # CurrentValueSubject 카드 상태
│   ├── NeighborhoodInsight.swift          # 집계 결과 모델
│   ├── InsightCard.swift                  # 카드 모델(상태·기준시각)
│   └── Cards/                             # 카드별 콘텐츠 뷰(Vitality/AirQuality/Transit/Amenity/Greenery/Safety/Events)
Service/
├── SeoulOpenAPI/
│   ├── Insight/NeighborhoodInsightService.swift   # 신규: 카드별 fetch 병렬 집계
│   ├── LivingPopulation/                  # 신규: 생활인구(자치구/행정동)
│   ├── AirQuality/                        # 신규: RealtimeCityAir
│   ├── Facilities/                        # 신규: 약국·화장실·와이파이·공원
│   ├── Safety/                            # 신규: 안심이CCTV·보안등·침수·범죄
│   ├── CulturalEvent/                     # 신규: 문화행사
│   ├── Transit/                          # 신규: 지하철(OA-22534)·버스(OA-15067/1094)
│   └── Bike/                             # 기존: 따릉이(OA-15493) 재사용
├── Geocoding/RegionCodeService.swift      # 신규: Kakao coord2regioncode
└── Data/SavedNeighborhoodStore.swift      # 신규: SwiftData(관심 동네)
Map/
├── MapViewController.swift                 # 변경: onLongPressDropped 콜백 + 핀
└── Annotation/InsightPinAnnotation.swift   # 신규(또는 DestinationAnnotation 재사용)
Coordinator/AppCoordinator.swift            # 변경: showNeighborhoodInsight + 배선
Common/Util/CoordinateTransform.swift       # 신규: TM/GRS80→WGS84 변환

NavigationTests/Insight/                    # 신규: 서비스·집계·좌표변환 테스트
```

**Structure Decision**: 기존 iOS 앱 구조(`Feature/`·`Service/`·`Map/`·`Coordinator/`)에 편입. 신규 화면 없이 `MapItemDetail` 팝업을 재사용하고, 서울 API는 기존 `Service/SeoulOpenAPI/`(따릉이/버스 패턴) 아래에 데이터셋별 클라이언트로 추가. PBXFileSystemSynchronizedRootGroup(auto-sync)이라 pbxproj 수동 참조 불필요.

## Complexity Tracking

> 위반 없음 — 해당 없음.
</content>
