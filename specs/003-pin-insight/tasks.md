# Tasks: 핀 기반 동네 인사이트

**Branch**: `003-pin-insight` | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Source root**: `Navigation/Navigation/Navigation/` · **Tests**: `Navigation/Navigation/NavigationTests/`

설계 입력: plan.md, research.md, data-model.md, contracts/seoul-apis.md, quickstart.md

---

## Phase 1: Setup

- [X] T001 `Secrets.xcconfig`에 Kakao REST 키 + 서울 열린데이터광장 인증키 항목 추가 (`Navigation/Secrets.xcconfig`, 커밋 금지) — ✅ `KAKAO_REST_API_KEY`·`SEOUL_OPEN_API_KEY` 이미 존재(재사용)
- [ ] T002 [P] 좌표 변환 유틸 추가 (TM EPSG:5174 / GRS80 UTM-K EPSG:5179 → WGS84) (`Common/Util/CoordinateTransform.swift`)
- [ ] T003 [P] 서울 OpenAPI 공통 요청 빌더·디코딩 헬퍼 (`Service/SeoulOpenAPI/SeoulAPIClient.swift`) — 따릉이 패턴 일반화

## Phase 2: Foundational (모든 스토리의 선행 — 완료 전 스토리 시작 불가)

- [X] T004 Insight 도메인 모델 정의: `NeighborhoodInsight`, `InsightCard`, `InsightCardKind`(7종), `CardState`(.loading/.loaded/.failed), `RegionCode`, `CardContent`(통합 표시 모델) (`Feature/Insight/NeighborhoodInsight.swift`, `Feature/Insight/InsightCard.swift`) — ✅ 작성
- [X] T005 `RegionCodeService` — Kakao `coord2regioncode`로 좌표→자치구/행정동 코드·명 (`Service/LBS/Kakao/RegionCodeService.swift` + `Model/KakaoRegionResponse.swift`) — ✅
- [X] T006 서울 영역 판정 + 서울 외 좌표 안내 처리 (FR-014) (`Service/LBS/Kakao/RegionCodeService.swift`) — ✅ 서울 외 시 팝업 미표시+핀 제거(안내 toast는 폴리시)
- [ ] T007 `NeighborhoodInsightService` 골격 — `TaskGroup` 병렬 집계 프레임 + 카드별 독립 상태 방출 (`Service/SeoulOpenAPI/Insight/NeighborhoodInsightService.swift`)
- [X] T008 `InsightViewModel` — `CurrentValueSubject`로 카드별 상태 스트림 (`Feature/Insight/InsightViewModel.swift`) — ✅ 골격(대기질, 슬라이스1)
- [X] T009 `MapViewController` 롱프레스 제스처 + `onLongPressDropped((CLLocationCoordinate2D)->Void)` 콜백 + 핀 표시(MKPointAnnotation) (`Map/MapViewController.swift`) — ✅
- [X] T010 `PinInsightContent: MapItemContent` — 헤더(주소)+카드 스크롤+푸터(경로) (`Feature/MapItemDetail/Content/PinInsightContent.swift` + `PinInsightContentView.swift`) — ✅
- [X] T011 `AppCoordinator.showNeighborhoodInsight(coord:)` 배선 — `onLongPressDropped` → region 해석 → `showMapItemDetail(content:)` (`Coordinator/AppCoordinator.swift`) — ✅

## Phase 3: User Story 1 — 핀으로 동네 종합 정보 보기 (P1) 🎯 MVP

**Goal**: 핀을 찍으면 7개 생활 지표 카드가 기존 POI 팝업에 표시된다.
**Independent Test**: 임의 서울 지점 롱프레스 → 활기·대기질·교통·편의·녹지·안전·행사 카드가 표시되고, 일부 실패해도 나머지 정상.

### Tests (US1)

- [ ] T012 [P] [US1] `CoordinateTransform` 변환 정확도 테스트 (`NavigationTests/Insight/CoordinateTransformTests.swift`)
- [ ] T013 [P] [US1] `NeighborhoodInsightService` 병렬 집계 + 부분 실패 격리 테스트(stub 주입) (`NavigationTests/Insight/InsightAggregationTests.swift`)

### Card data clients (US1) — 서로 다른 파일, 병렬 가능

- [ ] T014 [P] [US1] 생활인구 클라이언트 + 활기 등급 산출 (OA-14991, 행정동) (`Service/SeoulOpenAPI/LivingPopulation/LivingPopulationService.swift`)
- [X] T015 [P] [US1] 대기질 클라이언트 `RealtimeCityAir`(OA-1200, 자치구) + `asOf` (`Service/SeoulOpenAPI/AirQuality/AirQualityService.swift` + `RealtimeCityAirResponse.swift`) — ✅ (슬라이스 1)
- [ ] T016 [P] [US1] 교통 카드 — 따릉이(OA-15493, 기존 재사용)+지하철 최근접(OA-22534)+버스 최근접(OA-15067/1094) (`Service/SeoulOpenAPI/Transit/InsightTransitService.swift`)
- [ ] T017 [P] [US1] 편의 카드 — 약국(15000576)·공중화장실(파일)·공공와이파이(OA-20883), 카드별 반경(화장실/와이파이 300m, 약국 500m) (`Service/SeoulOpenAPI/Facilities/AmenityService.swift`)
- [ ] T018 [P] [US1] 녹지 카드 — 도시공원(15012890) 최근접/~1km (`Service/SeoulOpenAPI/Facilities/GreeneryService.swift`)
- [ ] T019 [P] [US1] 안전 카드 — 안심이CCTV(OA-20923)·보안등·침수흔적도(OA-15636, 점-폴리곤)·자치구 5대범죄(OA-13532) (`Service/SeoulOpenAPI/Safety/SafetyService.swift`)
- [ ] T020 [P] [US1] 지금 카드 — 문화행사(OA-15486) 반경 500m + 기간 (`Service/SeoulOpenAPI/CulturalEvent/CulturalEventService.swift`)

### Aggregation & display (US1)

- [ ] T021 [US1] `NeighborhoodInsightService`에 7개 카드 fetch 연결(병렬, 카드별 상태 방출) (`Service/SeoulOpenAPI/Insight/NeighborhoodInsightService.swift`)
- [ ] T022 [P] [US1] 카드 뷰 7종 구현(Theme 토큰·인디고·Dynamic Type) (`Feature/Insight/Cards/VitalityCardView.swift` 외 6개)
- [ ] T023 [US1] `PinInsightContent`에 `InsightViewModel` 바인딩 — 카드별 로딩/실패 상태, 실시간 `asOf`('○분 전'), 한 줄 요약 생성 (`Feature/MapItemDetail/Content/PinInsightContent.swift`)
- [ ] T024 [US1] 캐싱 적용 — 실시간 분 단위 / 준정적 일 단위 / 정적(화장실) 번들+`Documents/` 선적재 (`Service/SeoulOpenAPI/Insight/InsightCache.swift`)

**Checkpoint**: US1 단독으로 완전한 MVP — 핀→동네 인사이트 표시.

## Phase 4: User Story 2 — 인사이트에서 바로 길찾기 (P2)

**Goal**: 팝업 푸터의 경로 버튼으로 그 지점까지 길찾기 시작.
**Independent Test**: 인사이트 팝업에서 경로 버튼 → 해당 지점 경로 미리보기.

- [ ] T025 [US2] `PinInsightContent` 푸터에 경로 `FooterAction` 추가 → `onRouteTapped` → 기존 `AppCoordinator.showRoutePreview(to:)` 연결 (`Feature/MapItemDetail/Content/PinInsightContent.swift`, `Coordinator/AppCoordinator.swift`)

## Phase 5: User Story 3 — 관심 동네 저장·공유 (P3)

**Goal**: 동네 저장(재방문 시 최신 갱신) + 요약 공유.
**Independent Test**: 저장 후 목록에서 다시 열기 → 최신 재조회; 공유 동작.

- [ ] T026 [P] [US3] `SavedNeighborhood` SwiftData 모델 + `SavedNeighborhoodStore`(좌표·동네명·저장시각) (`Service/Data/SavedNeighborhoodStore.swift`)
- [ ] T027 [US3] 푸터 저장 `FooterAction` + 저장 로직, 관심 목록에서 다시 열 때 **최신 재조회**(스냅샷 미보존, FR-012) (`Feature/MapItemDetail/Content/PinInsightContent.swift`)
- [ ] T028 [P] [US3] 공유 `FooterAction` — 동네 요약 이미지/링크 공유 (`Feature/Insight/InsightShare.swift`)

## Phase 6: Polish & Cross-Cutting

- [ ] T029 [P] 로그 포인트 추가(quickstart): 핀 드롭→region→카드별→집계 시간 (`Feature/Insight/InsightViewModel.swift` 등)
- [ ] T030 [P] 성능 계측 — 첫 카드 <1.5s / 전체 <3s 로그 확인(SC-001) (`Service/SeoulOpenAPI/Insight/NeighborhoodInsightService.swift`)
- [ ] T031 [P] 라이트/다크 + Theme 토큰·접근성 점검(002 디자인 정합) (`Feature/Insight/Cards/*`)
- [ ] T032 [P] 단위 테스트 보강 — 카드별 반경 경계, `SavedNeighborhoodStore` 저장/재조회 (`NavigationTests/Insight/*`)
- [ ] T033 비침습 광고 슬롯 자리 확보(무료+광고 정체성 — 전면광고·도배 금지) (`Feature/MapItemDetail/Content/PinInsightContent.swift`)

---

## Dependencies

- **Phase 1 (Setup)** → **Phase 2 (Foundational)** → 이후 모든 스토리.
- **US1(P1)**: Foundational 완료 후 진행. T014~T020(카드 클라이언트, 병렬) → T021(집계) → T022(뷰, 병렬) → T023(바인딩) → T024(캐싱).
- **US2(P2)**: US1의 `PinInsightContent` 푸터 존재 전제. (Foundational 푸터 골격 T010 이후 독립 가능하나 US1 후 권장)
- **US3(P3)**: US1의 팝업·푸터 전제. T026(스토어)는 병렬 가능.
- **Polish**: 모든 스토리 후.

스토리 간 독립성: US2·US3는 US1 위에 푸터 액션만 추가 → US1이 MVP, US2/US3는 증분.

## Parallel Execution Examples

- **Foundational 내**: T002, T003 [P] 동시.
- **US1 카드 클라이언트**: T014~T020 [P] 7개 동시(서로 다른 파일).
- **US1 카드 뷰**: T022 [P] (클라이언트와 병렬 가능, 집계 T021과는 분리).
- **Polish**: T029~T032 [P] 동시.

## Implementation Strategy (MVP first)

1. **MVP = Phase 1 + 2 + US1(P1)**: 핀 → 동네 인사이트 표시. 단독 출시 가능한 가치.
2. **증분 1 = US2(P2)**: 경로 버튼(작은 추가).
3. **증분 2 = US3(P3)**: 저장·공유.
4. **Polish**: 로그·성능·디자인·테스트·광고 슬롯.

## Format Validation
- 모든 작업: 체크박스 + TaskID + (병렬 시 [P]) + (스토리 단계 시 [USx]) + 파일 경로 충족.
- Setup/Foundational/Polish: 스토리 라벨 없음. US1~US3: 라벨 있음.
</content>
