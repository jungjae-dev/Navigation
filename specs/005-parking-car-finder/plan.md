# Implementation Plan: 지하주차장 내 차 찾기

**Branch**: `008-parking-car-finder` | **Date**: 2026-07-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-parking-car-finder/spec.md`

## Summary

지도와 독립된 풀스크린 모듈. **등록** = 진입 즉시 카메라 스캔 → 주변 기둥 코드 자동 인식(Vision OCR) → 최근접 코드를 목표로 자동 저장(+인접 코드·인식 프레임 사진 부산물). **되찾기** = 같은 OCR+ARKit 앵커 엔진으로 랜드마크 맵을 세션 내 구축 → 누적 관측 전체로 단계적 격자 추정(2개 단일축=1D, 3개+=2D 아핀) → 2D HUD 화살표+신뢰도, 잔차 초과 시 근접확인 모드로 정직 강등, 목표 코드 연속 인식 시 도착. 좌표는 세션 한정 — 영속은 코드·층·사진·인접 관계(스칼라 거리)만 SwiftData. 디버그는 출시 빌드 포함·기본 off(DevToolsSettings 토글+히든 제스처), AR 공간 시각화 + NDJSON 관측 레코딩·리플레이.

**기술 확정(research)**: RealityKit ARView + UIKit 2D HUD(R1) · Vision 3Hz 스로틀 OCR(R2) · raycast 수직면 앵커, 실패 관측은 층/도착용(R3) · 등록 스켈레톤 템플릿 필터(R4) · 순수 GridEstimator 상태 기계(R5) · SwiftData 4번째 스토어(R6) · LocationRecorder 패턴 NDJSON(R7) · DevToolsSettings 확장(R8) · AppCoordinator 확장 + 스캔/되찾기 공용 AR VC(R9).

## Technical Context

**Language/Version**: Swift 6 (strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)

**Primary Dependencies**: UIKit(programmatic), ARKit(`ARWorldTrackingConfiguration`), RealityKit(ARView·디버그 엔티티), Vision(`VNRecognizeTextRequest`, 프로젝트 내 전례 있음), Combine, SwiftData, AVFoundation(권한·손전등), Swift Testing

**Storage**: SwiftData 신규 `Parking.store`(`ParkingSessionRecord` 1모델, 기존 3스토어 분리 패턴에 추가) + 사진 파일 `Documents/ParkingPhotos/` + 디버그 로그 `Documents/ParkingLogs/*.ndjson`

**Testing**: Swift Testing — 파서·GridEstimator·상태 기계 단위 + **현장 NDJSON 로그 픽스처 리플레이 테스트**(SC-009). AR·카메라는 실기기 검증(quickstart D1~D7)

**Target Platform**: iOS 26 (시뮬레이터 `iPhone 17 Pro`는 비AR 경로만). 풀 경험 기준=LiDAR 기종, 비 LiDAR는 폴백 중심 성립(스펙 가정)

**Project Type**: Mobile app 단일 타깃 (MVVM + Coordinator + Combine)

**Performance Goals**: OCR 3Hz 스로틀(발열 관리, NFR) · 관측 갖춰진 후 안내 표시 5초 내(SC-003) · 스캔 등록 15초 내 자동 완료(SC-001) · 디버그 off 시 오버헤드 0(DR-005)

**Constraints**: 카메라 영상 비저장(FR-022) · 좌표 영속화 금지(세션 종속) · 외부 인프라·네트워크 0(완전 로컬) · 신규 권한 NSCameraUsageDescription 1건

**Scale/Scope**: 신규 ~14 파일(Feature/ParkingFinder 7~8, Service/Parking 5~6, Model 1) + 배선(HomeDrawer 버튼, AppCoordinator, SceneDelegate 스토어, DevTools 토글·목록, Info.plist). 신규 화면 4(허브·AR 공용·수동 폼·사진 뷰어)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 원칙 | 평가 | 비고 |
|---|---|---|
| I. Swift 6 Concurrency | ✅ PASS | `ARSessionDelegate` = `nonisolated` + MainActor 홉(프로젝트 표준). Vision은 백그라운드 Task, 결과만 MainActor. 파서·추정기는 Sendable 순수 struct (R11) |
| II. MVVM + Coordinator + Combine | ✅ PASS | 상태 전부 `CurrentValueSubject`(GuidanceState·세션 상태), `@Published` 미사용. 전환은 `AppCoordinator.showParkingFinder()` + closure 콜백(기존 스타일). 신규 싱글턴 없음 — `DataService`·`DevToolsSettings` 확장 |
| III. 단순성 우선(YAGNI) | ✅ PASS | 본격 배치 매칭·멀티층·빈자리 Later 미선반영. 칼만/RANSAC 대신 배치 재피팅+잔차 규칙(R5). ARAnchor 수명 관리 생략(R3). 스캔/되찾기 공용 VC(R9) |
| IV. 로그 기반 검증 | ✅ PASS | `[ParkingFinder]` 로그 포인트 = 상태 전이·기각 사유·저장/완료(DR-004). quickstart S1~S2·D1~D7 로그 명세 + 리플레이 테스트 |
| V. iOS 26 / Xcode 26 | ✅ PASS | MKPlacemark 등 지도 API 미사용(지도 연동 없음). AR/Vision은 iOS 26 표준 API |
| Arch. 싱글턴 유지 | ✅ PASS | LocationService·NavigationSessionManager 미접촉(GPS 불사용 기능) |
| Arch. pbxproj auto-sync | ✅ PASS | 파일 추가만(자동 동기화). Info.plist 키 추가는 기존 예외 구성 활용 |
| Arch. API 키 | ✅ PASS | 네트워크·키 없음 |
| Workflow. 주석·테스트 | ✅ PASS | Swift Testing, 임계값 상수에만 튜닝 사유 주석 |

**결과**: PASS (Phase 1 재평가 동일). Complexity Tracking 불필요.

## Project Structure

### Documentation (this feature)

```text
specs/005-parking-car-finder/
├── plan.md              # 본 파일
├── research.md          # Phase 0 — R1~R11 결정 + 현장 튜닝 항목
├── data-model.md        # Phase 1 — 영속/런타임 2계층 + GuidanceState 상태 기계
├── quickstart.md        # Phase 1 — 시뮬레이터 S1~S2 / 실기기 D1~D7 / 유닛 테스트
├── contracts/
│   ├── parking-finder-ui.md        # 화면·HUD 상태·디버그 오버레이 계약
│   └── parking-observation-log.md  # NDJSON 이벤트 스키마 + 리플레이 계약
└── tasks.md             # /speckit-tasks 산출 (본 명령 아님)
```

### Source Code (repository root)

```text
Navigation/Navigation/
├── Feature/ParkingFinder/                          # [신규]
│   ├── ParkingSummaryViewController.swift            # 허브(요약 카드)+히든 제스처
│   ├── ParkingARViewController.swift                 # 스캔/되찾기 공용 (mode enum)
│   ├── ParkingARViewModel.swift                      # 파이프라인 상태 CurrentValueSubject
│   ├── ParkingManualEntryViewController.swift        # 수동 폴백 폼
│   ├── ParkingPhotoViewerViewController.swift        # 사진 확대
│   ├── ParkingFinderViewModel.swift                  # 세션 CRUD·수명주기 상태
│   └── Debug/
│       ├── ParkingDebugOverlayView.swift             # DR-002 스트립 + 인식 박스
│       └── ParkingDebugEntities.swift                # DR-001 RealityKit 시각화
├── Service/Parking/                                # [신규]
│   ├── PillarCodeParser.swift                        # 순수 — 토큰화·스켈레톤 필터 (R4)
│   ├── GridEstimator.swift                           # 순수 — 단계 피팅·잔차·상태 (R5)
│   ├── CodeScannerService.swift                      # ARFrame→Vision 스로틀 OCR (R2)
│   ├── ParkingEventRecorder.swift                    # NDJSON 기록 (R7)
│   └── ParkingEventReplayer.swift                    # 리플레이 (테스트·진단)
├── Model/
│   └── ParkingSessionRecord.swift                    # @Model + NeighborCode
└── [수정]
    ├── App/SceneDelegate.swift                       # Parking.store 구성 추가
    ├── Coordinator/AppCoordinator.swift              # showParkingFinder() + 분기
    ├── Feature/Home/HomeDrawerViewController.swift   # 진입 버튼(+활성 부제)
    ├── Service/Data/DataService.swift                # parking CRUD 확장
    ├── Service/DevTools/DevToolsSettings.swift       # parkingDebugEnabled
    ├── Feature/DevTools/DevToolsViewController.swift # 토글 행 + 로그 내보내기
    └── Info.plist                                    # NSCameraUsageDescription

NavigationTests/ParkingFinder/                      # [신규]
├── PillarCodeParserTests.swift
├── GridEstimatorTests.swift
├── ParkingReplayTests.swift                          # 현장 로그 픽스처 (SC-009)
├── ParkingSessionStoreTests.swift
└── Fixtures/*.ndjson
```

**Structure Decision**: 기존 `Feature/<기능>` + `Service/<도메인>` 관례 준수. 순수 계산(파서·추정기)을 Service로 분리해 리플레이 테스트 대상으로 고정. 별도 child coordinator 없음(단일 AppCoordinator 관례).

## 구현 순서 제안 (tasks 생성 참고)

1. **P0 — 순수 코어**: PillarCodeParser + GridEstimator + 상태 기계 + 유닛 테스트 (기기 불필요, 리스크 최전방)
2. **P1 — 데이터·허브**: ParkingSessionRecord/스토어 + Summary + ManualEntry + 진입 분기 (시뮬레이터 S1~S2 검증)
3. **P2 — AR 파이프라인**: CodeScannerService + ParkingARViewController(.scan → .find 순) (실기기 D1~D2)
4. **P3 — 강등·도착·배너**: 잔차 강등, 인접 신호, floorMismatch 등 (D3~D5)
5. **P4 — 디버그**: 오버레이·레코딩·리플레이·DevTools 배선 (D6) → 이후 현장 로그로 임계값 튜닝

## Complexity Tracking

> Constitution Check 위반 없음 — 해당 없음.
