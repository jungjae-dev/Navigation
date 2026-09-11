# Tasks: 지하주차장 내 차 찾기

**Input**: Design documents from `/specs/005-parking-car-finder/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: 포함 — constitution(Swift Testing)·plan(순수 코어 P0)·SC-009(리플레이)가 명시 요구. 순수 계산(파서·추정기)은 구현과 테스트를 짝으로 진행.

**Organization**: 유저 스토리별 독립 구현·검증. 각 스토리 체크포인트는 quickstart 시나리오 로그 확인(constitution IV).

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

**Purpose**: 권한·스토리지 기반 준비 (파일 추가는 pbxproj auto-sync — 수동 참조 금지)

- [X] T001 `Navigation/Navigation/Info.plist`에 `NSCameraUsageDescription` 추가 (auto-sync 예외 구성 활용)
- [X] T002 `Navigation/Navigation/App/SceneDelegate.swift`의 ModelContainer에 `Parking.store` ModelConfiguration 추가 (기존 3스토어 분리 패턴)
- [X] T003 [P] `NavigationTests/ParkingFinder/Fixtures/` 디렉터리 생성 + 합성 픽스처 자리(`synthetic-grid.ndjson` 주석 스켈레톤)

**Checkpoint**: 빌드 성공 + 앱 기동 시 스토어 4개 구성 로그

---

## Phase 2: Foundational (모든 스토리의 전제)

**Purpose**: 순수 파서·영속 모델·진입 배선 — US1~US3 공통 의존

- [X] T004 [P] `Navigation/Navigation/Model/ParkingSessionRecord.swift` — @Model(data-model 필드 전부) + `NeighborCode` Codable(`distanceToTarget: Double?`)
- [X] T005 [P] `Navigation/Navigation/Service/Parking/PillarCodeParser.swift` — 토큰화(층 B\d·지하\d / 구역 영문·한글 / 번호), 스켈레톤 유도(스캔 다수·수동 1개 코드), 템플릿 매칭 필터(번호판 기각), Sendable 순수 struct (R4)
- [X] T006 `NavigationTests/ParkingFinder/PillarCodeParserTests.swift` — 3 스켈레톤 패턴, 층 토큰 유무, 번호판 `12가3456` 기각, 오인식 문자 케이스
- [X] T007 `Navigation/Navigation/Service/Data/DataService.swift` parking CRUD 확장 — active ≤1 보장·대체(사진 삭제)·완료(최근 1건 보관, FR-019/021)
- [X] T008 `NavigationTests/ParkingFinder/ParkingSessionStoreTests.swift` — 수명주기(신규/대체/완료/보관 1건), in-memory 컨테이너
- [X] T009 `Navigation/Navigation/Coordinator/AppCoordinator.swift` — `showParkingFinder()` 풀스크린 present + 진입 분기(활성 기록·카메라 권한, UI 계약 표) + dismiss 배선
- [X] T010 `Navigation/Navigation/Feature/Home/HomeDrawerViewController.swift` — "내 차 찾기" 버튼(주차 아이콘, Theme 토큰) + 활성 기록 부제("B2-A-3 · 3시간 전")

**Checkpoint**: 파서·스토어 테스트 green + 홈 버튼 → 빈 화면 present 로그 `[ParkingFinder] entry: …`

---

## Phase 3: User Story 1 — 스캔 등록과 기억 확인 (P1) 🎯 MVP

**Goal**: 진입 → 몇 초 훑기 → 자동 저장(목표·인접·사진) → 요약 카드 → 재실행 후 유지

**Independent Test**: quickstart D1 (실기기) + 영속성 확인

- [X] T011 [P] [US1] `Feature/ParkingFinder/ParkingFinderViewModel.swift` — 세션 상태·수명주기 액션 `CurrentValueSubject`(저장/대체/완료/목표 수정)
- [X] T012 [P] [US1] `Service/Parking/CodeScannerService.swift` — `ARFrame.capturedImage` 3Hz 스로틀 → Vision `VNRecognizeTextRequest`(ko/en, .accurate, 보정 off), 백그라운드 Task, 동시 1건 (R2)
- [X] T013 [US1] `Feature/ParkingFinder/ParkingARViewController.swift` — ARView + `ARWorldTrackingConfiguration` 세션, `nonisolated` delegate + MainActor 홉(R11), mode enum(.scan/.find) 뼈대, 닫기
- [X] T014 [US1] `Feature/ParkingFinder/ParkingARViewModel.swift` — .scan 파이프라인: OCR 결과→파서→관측 누적(hit 2 확정)→raycast 앵커(R3)→최근접(전부 위치 실패 시 최다 관측) 목표 선정→3초 안정화 자동 저장→인접 관계(스칼라 거리, 실패 쌍 nil) (FR-002/002a/002b)
- [X] T015 [US1] 인식 프레임 사진 자동 저장 — `Documents/ParkingPhotos/` JPEG + 경로를 세션에 기록, 완료·대체 시 파일 삭제는 T007 로직 사용 (`ParkingARViewModel.swift` + `DataService.swift`)
- [X] T016 [US1] 층 확인 시트 — 층 토큰 없을 때 저장 직전 표시(B1~B5·기타·모름) (`ParkingARViewController.swift`, FR-005)
- [X] T017 [P] [US1] 손전등 토글 — AVCaptureDevice torch, 세션 재시작 시 재적용 (`ParkingARViewController.swift`, FR-018)
- [X] T018 [P] [US1] `Feature/ParkingFinder/ParkingSummaryViewController.swift` — 허브: 코드(최대 강조)·층·경과시간·사진 썸네일, [안내 시작][✓ 찾았어요][새 위치 등록](대체 확인 얼럿), 저장 직후 "저장되었습니다"+인식 코드 목록으로 목표 즉시 교체(FR-001a/002a), Theme 토큰
- [X] T019 [P] [US1] `Feature/ParkingFinder/ParkingPhotoViewerViewController.swift` — 핀치줌 뷰어
- [X] T020 [US1] 스캔 보조 흐름 — 미저장 이탈 확인 얼럿, 15초 무확보 시 "직접 입력할까요?" 배너(화면 전환은 T033) (`ParkingARViewController.swift`)
- [ ] T021 [US1] **체크포인트** ⏳ 실기기 현장 검증 대기: quickstart D1 실기기 — 스캔 자동 저장·인접·사진 로그 + 앱 재실행 요약 카드 직행 확인

---

## Phase 4: User Story 2 — 카메라 방향 안내로 차 되찾기 (P2)

**Goal**: 단계적 격자 안내(1D→2D) + 정직 강등 + 도착 확정

**Independent Test**: quickstart D2~D5·D7 (실기기, US1 데이터 전제)

- [X] T022 [P] [US2] `Service/Parking/GridEstimator.swift` — xz 투영, 단계 피팅(2개 단일축 1D/혼합축·목표 축 밖→needMoreObservation(missingAxis)/3+점 아핀 정규방정식), 잔차 강등·정합 2연속 복귀, 신뢰도 3단계, 도착 판정(연속 2회·1초), Sendable 순수 (R5, FR-009/012/013)
- [X] T023 [P] [US2] `NavigationTests/ParkingFinder/GridEstimatorTests.swift` — 동구역 2개/동번호 2개/혼합축/목표 축 밖/3점 아핀 외삽 정확도/스네이크 잔차 강등·복귀/도착/합성 픽스처
- [X] T024 [US2] `ParkingARViewModel.swift` .find 파이프라인 — 저장 세션 로드(스켈레톤 필터 시드)→관측→GridEstimator→`CurrentValueSubject<GuidanceState>`; 위치 실패 관측은 층·도착 전용(FR-015)
- [X] T025 [US2] find HUD — GuidanceState별 오버레이: searching/needMore 문구(부족 축 특정), 2D 회전 화살표+거리+신뢰도 점+단계 라벨, degraded 카드(사진 썸네일), arrived 풀오버레이+[찾았어요] (`ParkingARViewController.swift` + HUD 서브뷰, UI 계약 표)
- [X] T026 [US2] 배너 레이어 — floorMismatch("B2로 이동"/층 미상 "B2에 주차하셨습니다"), trackingLimited, anchorFailing(연속 3회→손전등 제안) (`ParkingARViewController.swift`, FR-014/015)
- [X] T027 [US2] 인접 코드 근접 신호 — 저장 인접 목격 시 신뢰도 +1단계·도착 보조 (`GridEstimator.swift`, FR-013a)
- [X] T028 [US2] 백그라운드/중단 복귀 — 관측 전체 무효화 → searching 재시작 토스트, 세션 인터럽션 delegate (`ParkingARViewController.swift`)
- [X] T029 [US2] `[ParkingFinder]` 로그 포인트 정비 — quickstart "로그 설계" 준수: info=흐름 뼈대(진입·채택/기각·격자 갱신·상태 전이·저장), debug=중간 컨텍스트(개별 인식·좌표·각도), 고빈도는 NDJSON 전용 (DR-004, quickstart 로그 문자열과 일치)
- [ ] T030 [US2] **체크포인트** 부분 확인(260801 로그): D2 단계전환·화살표 부호 ✓, D4 도착 확정 ✓, D5 배너 ✓ — D3 강등만 미검증(스네이크 주차장 필요): quickstart D2(단계 전환)·D3(강등·복귀)·D4(도착·오채택 0)·D5(실패 경로)·D7(백그라운드) 실기기 로그

---

## Phase 5: User Story 3 — 수동 등록 폴백 (P3)

**Goal**: 권한 거부·인식 불가 환경에서도 최소 가치 성립

**Independent Test**: quickstart S1~S2 (시뮬레이터)

- [X] T031 [P] [US3] `Feature/ParkingFinder/ParkingManualEntryViewController.swift` — 코드 입력·층 선택·사진 첨부(선택)·저장→Summary, 수동 코드 1개 스켈레톤 시드(FR-008), Theme 토큰
- [X] T032 [US3] 권한 거부 경로 — 진입 분기 manual 기본(T009 분기 완성), Summary [안내 시작]·[촬영 인식]→설정 안내 시트 (`AppCoordinator.swift`, `ParkingSummaryViewController.swift`, FR-017)
- [X] T033 [US3] 스캔 15초 배너 → ManualEntry 전환 배선 (`ParkingARViewController.swift` ↔ coordinator, FR-004)
- [X] T034 [US3] 파싱 불가 세션 find — degraded 고정 시작(격자·화살표 미노출, 목표 직접 인식+층 상기+사진) (`ParkingARViewModel.swift`, FR-016 — T024 이후)
- [ ] T035 [US3] **체크포인트** ⏳ 시뮬레이터 수동 확인 필요: quickstart S1(권한 거부 수동 등록·영속성)·S2(층 시트·수명주기) 시뮬레이터 로그

---

## Phase 6: 개발 지원 도구 (DR-001~005) — US2 현장 튜닝의 전제

- [X] T036 [P] `Service/DevTools/DevToolsSettings.swift`에 `parkingDebugEnabled` 추가(UserDefaults+CurrentValueSubject 패턴) + `Feature/DevTools/DevToolsViewController.swift` 토글 행 (DR-005)
- [X] T037 히든 제스처 — Summary 경과시간 라벨·AR 상단 안내 문구 5회 탭 → 토글+스낵바 (`ParkingSummaryViewController.swift`, `ParkingARViewController.swift`)
- [X] T038 [P] `Feature/ParkingFinder/Debug/ParkingDebugOverlayView.swift` — DR-002 상태 스트립(상태·관측 n·잔차·신뢰) + 인식 박스(채택 초록/기각 빨강+사유), off 시 미생성
- [X] T039 [P] `Feature/ParkingFinder/Debug/ParkingDebugEntities.swift` — DR-001 RealityKit: 앵커 빌보드 라벨(신뢰 색)·격자 축·고스트 격자점·목표 마커·잔차선·궤적 + ARKit debugOptions 토글(스트립 롱프레스)
- [X] T040 [P] `Service/Parking/ParkingEventRecorder.swift` — contracts/parking-observation-log.md 스키마 NDJSON 기록(`Documents/ParkingLogs/`), 토글 off 시 무비용 (DR-003)
- [X] T041 `Service/Parking/ParkingEventReplayer.swift` + `NavigationTests/ParkingFinder/ParkingReplayTests.swift` — codeObserved/devicePose 재투입→gridUpdated·stateTransition·화살표 각도 재계산이 기록과 일치(리플레이 계약, SC-009)
- [X] T042 DevTools에서 ParkingLogs 파일 목록·공유 내보내기 (`Feature/DevTools/` — RecordingFileList 패턴 준용)
- [ ] T043 **체크포인트** 부분 확인: 레코딩 생성·내보내기 실사용 ✓(260710/260801 로그 수령) — 오버레이 표시·off 무흔적은 화면 확인 필요: quickstart D6 — 제스처 토글→오버레이 표시→ndjson 생성→내보내기, off 시 오버레이·기록 없음

---

## Phase 7: 현장 튜닝·스파이크 & 마감

- [X] T044 [스파이크] 완료: 주차장 2곳(260710 번호단독 N / 260801 구역+번호 ZN), 픽스처 4건 커밋, 버그 2건 수정(선행0·리플레이어 패리티) — 실주차장 2곳 이상 현장 세션(D1~D5 수행) — DR-003 로그 수집 → `NavigationTests/ParkingFinder/Fixtures/*.ndjson` 픽스처 커밋 + 리플레이 테스트 케이스화
- [ ] T045 임계값 튜닝 (상수 집결은 ParkingTuning.swift로 완료 — 조정은 현장 로그 대기) — research 표(OCR 신뢰도 0.6/잔차 max(3m,간격×0.7)/도착 연속 2회/스캔 유예 3초·15초) 상수를 `Service/Parking/ParkingTuning.swift`로 모으고 현장 로그 기반 조정(튜닝 사유 주석)
- [ ] T046 [P] [스파이크] ⏳ 비 LiDAR 실기기 대기 — 비 LiDAR 기종 raycast 성공률 비교 → research.md 갱신 + 필요 시 폴백 문구 조정 (스파이크 2)
- [ ] T047 [P] [스파이크] ⏳ 현장 수집 대기 — 주차장 5~10곳 코드 포맷 수집(층 토큰 유무·스네이크 여부) → 파서 스켈레톤·테스트 보강 (스파이크 3, T044 로그 겸용)
- [ ] T048 최종 회귀 (사전 회귀 완료: 주차 테스트 전부 green, MapMatcher·TurnType 각 1건 실패는 main에도 존재하는 기존 결함 — 본 기능 무관. 최종 회귀는 현장 체크포인트 후) — quickstart 전체(S1~S2·D1~D7) + SC-001~009 대조, 완료 기록 작성

---

## Dependencies

```
Phase 1 → Phase 2 → US1(P3단계) → US2(P4) → US3(P5) → DR(P6) → 튜닝(P7)
                         │                    ▲
                         └── US3의 T031~T033은 US1의 AR/Summary만 필요(US2 불필요) ──┘
                             T034만 US2(T024) 이후
DR(P6)은 US2 완료 전에도 착수 가능(T036~T040은 독립) — 단 T041은 T022·T024 이후
T044~T047(현장)은 T043(디버그 도구) 이후가 효율적
```

- 스토리 독립성: US1 단독 = MVP 성립. US3(T031~T033)은 US2 없이 테스트 가능. US2는 US1 데이터 전제.
- 순수 코어 선행: T005/T006(파서)은 Phase 2, T022/T023(추정기)은 US2 최선두 — 기기 없이 리스크 소진(plan 구현 순서 P0 원칙).

## Parallel Example

- Phase 2: T004 ∥ T005 (모델·파서 서로 독립) → 이후 T006 ∥ T007
- US1: T011 ∥ T012 → T013·T014 순차 → T017 ∥ T018 ∥ T019
- US2: T022 ∥ T023 (구현·테스트 짝) 후 T024부터 순차
- P6: T036 ∥ T038 ∥ T039 ∥ T040

## Implementation Strategy

1. **MVP = Phase 1+2+US1** — "스캔 등록+기억 확인"만으로 출시 가능한 가치. 시뮬레이터 검증 한계(카메라) 때문에 T021부터 실기기 필요.
2. US2가 기술 리스크의 전부 — GridEstimator(T022/023)를 합성 데이터로 먼저 green, AR 배선(T024~)은 그 뒤.
3. DR 도구(P6)를 US2 현장 검증(D2~D5) 전에 완성하면 튜닝 사이클(P7)이 로그 기반으로 돌아감 — T030 체크포인트를 P6 이후 재수행해도 좋음.
4. 커밋 단위: 태스크 또는 체크포인트 단위, 브랜치 `008-parking-car-finder` 유지.
