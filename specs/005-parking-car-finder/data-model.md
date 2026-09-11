# Data Model — 지하주차장 내 차 찾기

두 계층으로 구분: **영속 계층**(SwiftData — 세션을 넘어 유효한 것만)과 **런타임 계층**(AR 세션 수명 — 좌표 포함, 절대 저장 금지).

---

## 영속 계층 (SwiftData `Parking.store`)

### ParkingSessionRecord (@Model)

한 번의 주차. 활성 레코드는 항상 ≤1 (FR-019).

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | UUID | 식별자 |
| `targetCodeRaw` | String | 목표 기둥 코드 원문 ("B2-A-3") |
| `floorToken` | String? | 층 ("B2"). 코드 내 표기 또는 별도 입력 |
| `floorSource` | String | `"code"` \| `"manual"` — 층 출처 (FR-005/014 문구 분기용) |
| `zoneToken` | String? | 구역 ("A") — 파싱 실패 시 nil (폴백 전용 모드) |
| `numberValue` | Int? | 번호 (3) — 파싱 실패 시 nil |
| `templateSkeleton` | String | 코드 구조 스켈레톤 ("F-Z-N" 등) — 되찾기 필터(FR-008) 시드 |
| `photoPaths` | [String] | `Documents/ParkingPhotos/` 상대 경로. 인식 프레임 자동 + 수동 추가 |
| `createdAt` | Date | 주차 시각 (FR-002) |
| `status` | String | `"active"` \| `"completed"` |
| `completedAt` | Date? | 완료 시각 |
| `neighborsData` | Data | `[NeighborCode]` JSON 인코딩 (아래) |

**수명주기** (FR-019/021):
```
등록 → active ── 도착 확정 or [찾았어요] ──▶ completed
         │                                   └─ 최근 1건만 보관, 이전 completed 레코드+사진 삭제
         └─ 새 등록 시: 안내 후 기존 active를 삭제(사진 포함)하고 신규 active 생성
```

**검증 규칙**: `targetCodeRaw` 비어있지 않음. `floorToken == nil`이면 등록 UI가 층 확인 강제(FR-005) — 사용자가 "모름" 선택 시에만 nil 허용. active 레코드 삽입 전 기존 active 존재 여부 검사.

### NeighborCode (Codable — neighborsData 내부)

스캔 부산물(FR-002b). **좌표·벡터 저장 금지** — 세션 좌표계 종속. 회전 불변인 것만.

| 필드 | 타입 | 설명 |
|---|---|---|
| `codeRaw` | String | 인접 코드 원문 ("A-4") |
| `zoneToken` | String? / `numberValue` Int? | 파싱 토큰 |
| `distanceToTarget` | Double? | 목표 앵커까지 스칼라 거리(m) — 회전 불변. **등록 스캔에서 어느 한쪽 위치 파악 실패 시 nil**(근접 신호 FR-013a는 목격 자체로 동작하므로 손실 없음) |

용도: 되찾기 중 목격 시 근접 신호(FR-013a), 템플릿 필터 보강(FR-008).

---

## 런타임 계층 (AR 세션 수명 — 비영속)

### CodeObservation

인식된 기둥 코드 1개의 누적 관측. `[String: CodeObservation]` (키=정규화 코드).

| 필드 | 타입 | 설명 |
|---|---|---|
| `codeRaw` / `parsed` | String / ParsedCode | 원문·토큰 |
| `position` | simd_float3? | 세션 월드 좌표. **nil = raycast 실패 관측**(FR-015: 층·도착용만) |
| `hitCount` | Int | 관측 횟수 (2회↑ 확정 — R4) |
| `firstSeenAt` / `lastSeenAt` | Date | 도착 연속 인식 판정(FR-013)·재앵커(FR-011) |

### ParsedCode (순수 struct)

`floorToken: String?`, `zoneToken: String?`, `zoneIndex: Int?`(A=0,B=1… / 가=0,나=1…), `numberValue: Int?`, `skeleton: String`.
파서 규칙: research R4. 번호판·안내문은 skeleton 불일치로 여기 도달 전 기각.

### GridModel (GridEstimator 출력, 순수 struct)

| 필드 | 타입 | 설명 |
|---|---|---|
| `stage` | GridStage | `.insufficient` / `.axis1D(축종류)` / `.affine2D` |
| `origin`, `rowVec`, `colVec` | simd_float2 (xz 평면) | 아핀 모델. axis1D면 한 축만 유효 |
| `residualRMS` | Double | 잔차 — 강등 판정 입력 |
| `targetEstimate` | simd_float2? | 목표 외삽 위치 (가상 핀) |
| `confidence` | Confidence | `.low / .medium / .high` (관측 수+잔차) |

### GuidanceState (상태 기계 — UI·디버그·로그의 공통 기준)

```
searching ──2개 단일축──▶ axisGuidance ──3개+ 비공선──▶ gridGuidance
   │  ▲                       │                            │
   │  └── 관측 무효화(백그라운드 복귀 등) ◀──────────────────────┤
   ├─ 혼합축 2개, 또는 단일축 확보했으나 목표가 축 밖           │ 잔차>임계 (FR-012)
   │    → needMoreObservation(missingAxis)                   │
   │                                                        ▼
   │              정합 관측 2연속 ◀──────────────────────  degraded
   └────── 목표 코드 연속 안정 인식(FR-013) — 어느 상태에서든 ──▶ arrived
```

부속 배너(상태와 직교, 겹침 가능): `floorMismatch(현재층)`, `trackingLimited(사유)`, `anchorFailing`(→ 손전등 제안).

**파싱 불가 세션**(zoneToken/numberValue == nil로 저장된 기록): 격자 추정 불가 → 상태 기계를 `degraded`(근접확인 모드) 고정으로 시작. 목표 코드 직접 인식(도착)·층 상기·사진 폴백만 제공(FR-016).

전이 이벤트는 전부 Logger + ParkingEventRecorder 기록(DR-004).

### DeviceContext (매 프레임 갱신, 비저장)

`position: simd_float3`, `heading: simd_float2(xz)` — 화살표 각도 = `atan2(targetEstimate − position, heading)`. 1Hz로 이벤트 로그에 기록(DR-003, 화살표 재계산 검증용).

---

## 레코딩 이벤트 (NDJSON — contracts/parking-observation-log.md에 스키마)

`codeObserved` / `raycastFailed` / `trackingChanged` / `devicePose` / `guidanceShown` / `stateTransition`(기각·강등 사유 포함). 리플레이 시 이 스트림만으로 GridModel·GuidanceState 시퀀스가 결정적으로 재구성됨(SC-009).

---

## 관계도

```
[영속] ParkingSessionRecord ──1:N──▶ NeighborCode (JSON blob)
              │ targetCodeRaw / templateSkeleton
              ▼ (되찾기 시작 시 로드)
[런타임] PillarCodeParser ──▶ CodeObservation{} ──▶ GridEstimator ──▶ GridModel + GuidanceState
              ▲                                                            │
        Vision OCR ◀── ARFrame                            UIKit HUD / RealityKit 디버그 / Recorder
```
