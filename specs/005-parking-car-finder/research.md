# Research — 지하주차장 내 차 찾기

Phase 0 산출물. Technical Context의 미지수를 결정으로 확정한다.
전제: 절대 측위 아님(점진적 방향 추정), 사전 인프라 0, 완전 로컬. 스펙 Clarifications(허브 구조·스캔 등록·디버그 토글) 반영.

---

## R1. AR 스택 — ARKit + RealityKit(ARView), 사용자 HUD는 UIKit 2D

**Decision**: `ARWorldTrackingConfiguration` + RealityKit `ARView`. 공간 디버그 요소(앵커 라벨·격자 축·고스트 격자점·잔차선)는 RealityKit 엔티티. **사용자용 방향 표시는 3D가 아니라 UIKit 2D HUD**(회전하는 화살표 + 거리/신뢰도 텍스트)로 ARView 위에 오버레이.

**Rationale**:
- RealityKit `ARView.debugOptions`(`.showFeaturePoints`, `.showWorldOrigin`, `.showAnchorOrigins`, `.showStatistics`)가 DR-001의 기반 계층을 공짜로 제공 — 트래킹 문제 vs 알고리즘 문제를 현장에서 즉시 구분.
- 사용자 화살표를 2D HUD로 하는 이유: ① 추정은 불확실한데 3D 고정 화살표는 과신을 유발(FR-010 "과신 금지"와 충돌) ② 가림·조명 문제 없음 ③ 구현 단순. 화살표 각도 = `atan2(목표-기기 벡터 vs 기기 heading)` — 세션 좌표계 내 순수 계산.
- LiDAR 기종은 `sceneReconstruction` 없이도 raycast가 depth 활용 → 별도 분기 코드 불필요(ARKit이 내부 처리).

**Alternatives**: SceneKit(`ARSCNView`) — 가능하나 신규 코드에 legacy 스택 채택 이유 없음. 3D 화살표 엔티티 — 과신 유발 + 구현 비용, 기각.

## R2. OCR — Vision `VNRecognizeTextRequest`, ARFrame 스로틀 처리

**Decision**: `ARSessionDelegate.session(_:didUpdate frame:)`에서 **~3Hz로 스로틀**(10프레임당 1회)해 `ARFrame.capturedImage`를 `VNRecognizeTextRequest`로 처리. `recognitionLevel = .accurate`, `recognitionLanguages = ["ko-KR", "en-US"]`, `usesLanguageCorrection = false`(코드는 자연어가 아님). 백그라운드 큐 처리, 진행 중이면 프레임 스킵(동시 1건).

**Rationale**: 프로젝트에 Vision 사용 전례 있음(`LiftSubjectService`). `.accurate`가 표지판 같은 프린트 텍스트에 유리하고 3Hz면 충분(사용자가 카메라를 천천히 훑음). 언어 보정 off — "B2-A-3"을 단어로 교정하려는 시도 차단.

**Alternatives**: `.fast` 레벨 — 저조도 정확도 손실, 기각. 매 프레임 처리 — 발열·배터리(NFR), 기각. `VNDetectTextRectanglesRequest`+커스텀 — 과잉, 기각.

## R3. 텍스트 → 3D 앵커 — Vision 박스 중심 raycast, 실패 시 관측만 유지

**Decision**: 인식 텍스트의 bounding box 중심(Vision 정규좌표)을 뷰 좌표로 변환 → `arView.raycast(from:allowing:.estimatedPlane, alignment:.vertical)` (기둥=수직면), 실패 시 `.any` 재시도. 성공 → `{코드 → simd_float3}` 관측 등록(같은 코드 재관측 시 위치 갱신=재앵커, FR-011). **raycast 실패 시 코드는 "위치 없는 관측"으로 등록** — 층 확인·도착 확정에 사용, 격자 피팅 제외(FR-015). 실패 카운터가 임계(연속 3회) 넘으면 "더 가까이/손전등" 배너.

**Rationale**: 표준 파이프라인. LiDAR 기종에서 자동 고정밀. 관측을 ARAnchor로 등록하지 않고 위치 값만 보관 — 앵커 수명 관리 비용 제거, 재관측 갱신이 더 단순(어차피 매 관측마다 전체 재피팅).

**Alternatives**: `ARAnchor` 등록 + 트래킹 위임 — 재정렬 로직이 복잡해지고 이점 없음, 기각. depth map 직접 샘플링 — LiDAR 전용 분기 발생, 기각.

## R4. 코드 파싱 + 오검출 필터 — 순수 파서 + 등록 템플릿 매칭

**Decision**: `PillarCodeParser`(순수 Swift, 테스트 대상):
1. **토큰화**: 층 토큰(`B\d`, `지하\d`, `\dF`), 구역 토큰(영문 1–2자 또는 한글 1자 가-힣), 번호 토큰(`\d{1,3}`)을 구분자(-, 공백, ·, /) 기준 분해.
2. **템플릿**: 등록 스캔에서 확보된 코드들로부터 구조 스켈레톤(예: `층-구역-번호`, `구역번호` 결합형) 확정 → 되찾기 때 **같은 스켈레톤과 일치하는 후보만 채택**(FR-008). 번호판(`12가3456` = 숫자+한글+4자리숫자)은 스켈레톤 불일치로 자동 기각.
3. 신뢰도: Vision confidence < 0.6 기각 + 동일 텍스트 2회 관측 시 확정(오인식 완화).

**Rationale**: "범용 파싱"을 "이 주차장의 템플릿 매칭"으로 축소 — 브리프의 최대 난제 완화. 순수 함수라 리플레이 테스트로 고정 가능.

**Alternatives**: ML 분류기 — 데이터 없음·과잉, 기각. 정규식 하드코딩 목록만 — 스켈레톤 학습 없이는 번호판 필터가 약함, 기각.

## R5. 격자 추정 — 순수 `GridEstimator`, 단계적 + 잔차 상태 기계

**Decision**: 수평면(월드 xz, ARKit은 중력 정렬) 투영 후:
- **관측 1개**: `.searching`
- **2개 단일축 차이**: 해당 축 단위벡터 = Δ위치/Δ인덱스 → 1D 외삽 `.axisGuidance` (목표가 그 축 위일 때만)
- **2개 혼합축**: `.needMoreObservation(missingAxis:)` — 부족한 축 특정 안내
- **3개+ 비공선**: 최소제곱 아핀 피팅(미지수 6: origin, rowVec, colVec — 정규방정식 직접 해) → `.gridGuidance`
- **잔차 감시**: 신규/재관측마다 예측-관측 거리 계산. `잔차 > max(3.0m, 기둥간격 추정치×0.7)` → `.degraded`(근접확인 모드). 이후 정합 관측 2회 연속 → 복귀(FR-012)
- **신뢰도**: 관측 수 + 잔차 RMS 기반 3단계(높음/중간/낮음)
- **도착**: 목표 코드 연속 2회(≥1초 간격) 안정 인식 → `.arrived`(FR-013). 저장된 인접 코드 목격 → 신뢰도 1단계 상승 + 도착 판단 보조(FR-013a)

**Rationale**: 스펙 FR-009/012의 직접 구현. 전부 순수 계산 → DR-003 리플레이·유닛 테스트로 검증(SC-009). 임계값들은 상수로 모아 현장 튜닝 대상 명시.

**Alternatives**: 칼만/파티클 필터 — 관측 수가 적어(3~10) 배치 재피팅이 더 단순·투명, 기각(YAGNI). RANSAC 완전 구현 — 관측 수 적어 잔차 기각 규칙으로 충분, 단순화.

## R6. 영속성 — SwiftData 4번째 스토어 + 사진 파일

**Decision**: `Parking.store`를 `SceneDelegate`의 `ModelContainer`에 4번째 `ModelConfiguration`으로 추가(기존 Favorites/SearchHistory/Recordings 분리 패턴). `@Model ParkingSessionRecord` 1개. 사진은 `Documents/ParkingPhotos/`에 JPEG 파일(인식 프레임 자동 캡처), 경로만 저장. 완료 시 최근 1건 외 레코드·사진 삭제(FR-021). 인접 코드는 **코드 문자열+파싱 토큰+목표까지 스칼라 거리**로 저장 — 좌표·벡터는 세션 종속이라 저장 금지(스펙 Key Entities), 스칼라 거리는 회전 불변이라 유효.

**Rationale**: 기존 스토어 분리 원칙 준수. `DataService`에 parking 메서드 확장(기존 싱글턴 재사용, 신규 싱글턴 금지).

## R7. 관측 레코딩/리플레이 — NDJSON, `LocationRecorder` 패턴 준용

**Decision**: `ParkingEventRecorder` — `Documents/ParkingLogs/<세션시각>.ndjson`. 이벤트 스키마(contracts/parking-observation-log.md): `codeObserved`(원문·토큰·위치·신뢰도), `raycastFailed`, `trackingChanged`, `devicePose`(1Hz 스로틀), `guidanceShown`(화살표 각도·상태·신뢰도), `stateTransition`(기각 사유 포함). `ParkingEventReplayer`가 로그를 `GridEstimator`+파서에 재투입 — 유닛 테스트 픽스처 + 디버그 재현(DR-003). 지각 계층(영상)은 비기록 — 진단은 실패 이벤트로.

**Rationale**: `LocationFileWriter`(NDJSON append) 구조 재사용. 추정 로직이 순수라 "같은 입력=같은 출력" 보장.

## R8. 디버그 토글(DR-005) — DevToolsSettings 확장 + 히든 제스처

**Decision**: `DevToolsSettings`에 `parkingDebugEnabled: CurrentValueSubject<Bool,_>` 추가(UserDefaults 지속, 기존 패턴). 활성화 경로 2개: ① 기존 DevTools 메뉴에 토글 행 추가 ② ParkingFinder 화면 내 히든 제스처 — **요약 화면 경과시간 라벨 5회 연속 탭**. 출시 빌드 포함, 기본 off. off일 때 오버레이·레코딩·디버그 엔티티 전부 미생성(성능 영향 0, DR-005). 레코딩 파일은 DevTools 파일 목록에서 공유 시트로 내보내기.

**Rationale**: 개발자 메뉴가 이미 존재 — 신규 인프라 불필요. 제스처는 우연 발견이 어렵고 심사 안전.

## R9. 화면·코디네이터 — AppCoordinator 확장, 모듈 내 4 VC

**Decision**: `AppCoordinator.showParkingFinder()` — `UINavigationController` 풀스크린 present(기존 present 패턴). 내부: `ParkingSummaryViewController`(허브), `ParkingARViewController`(**스캔/되찾기 공용, mode enum** — AR·OCR·디버그 오버레이 90% 공유), `ParkingManualEntryViewController`(폴백 폼), `ParkingPhotoViewerViewController`. 진입 분기(활성 기록 유무)는 coordinator에서. 화면 간 전환은 기존 스타일(closure 콜백 → coordinator).

**Rationale**: 별도 child coordinator는 이 프로젝트 패턴에 없음(단일 AppCoordinator 유지). 스캔/되찾기를 한 VC+mode로 — 파이프라인 전부 공유, 다른 건 HUD와 완료 동작뿐(YAGNI).

## R10. 권한·손전등·백그라운드

**Decision**:
- `NSCameraUsageDescription` Info.plist 추가(auto-sync 예외 이미 구성됨). `AVCaptureDevice.authorizationStatus(for:.video)` 분기 — 거부 시 수동 폼 기본(FR-017).
- 손전등: `AVCaptureDevice.default(for: .video)`의 `torchMode` — ARSession 실행 중에도 device lock으로 제어 가능(알려진 기법). 세션 재시작 시 torch 재적용.
- 백그라운드 복귀: `sessionWasInterrupted`/`sessionInterruptionEnded` → 관측 전체 무효화 + `.searching` 재시작(스펙 엣지 케이스). `relocalization` 시도 안 함(코드 재인식이 더 빠르고 확실).

## R11. Swift 6 Concurrency 배치

**Decision**: `ARSessionDelegate`는 `nonisolated` + 내부에서 `MainActor.assumeIsolated`/`Task { @MainActor }` 홉(프로젝트 표준 패턴). Vision 처리는 detached Task(백그라운드) → 결과만 MainActor로. `GridEstimator`·`PillarCodeParser`는 순수 `Sendable` struct. 상태는 `CurrentValueSubject`(MainActor 소유).

## 미해결 → 현장 튜닝 항목 (스파이크, plan 차단 아님)

| 항목 | 초기값 | 튜닝 방법 |
|---|---|---|
| OCR 스로틀/신뢰도 임계 | 3Hz / 0.6 | 실주차장 DR-003 로그 |
| 잔차 강등 임계 | max(3.0m, 간격×0.7) | 스네이크 주차장 현장 시험 |
| 도착 확정 조건 | 연속 2회·1초 간격 | 오확정 0 목표로 조정 |
| 비 LiDAR raycast 성공률 | 미지 | 기종 2대 비교(스파이크 2) |
| 코드 스켈레톤 커버리지 | 3패턴 | 주차장 5~10곳 수집(스파이크 3) |
