# Quickstart — 지하주차장 내 차 찾기 검증

constitution 원칙 IV: Phase 완료 기준은 빌드 성공이 아니라 **예상 로그 확인**. 로그 프리픽스 `[ParkingFinder]`.

## 로그 설계 (os.Logger, category: "ParkingFinder")

- **`.info` = 흐름의 뼈대** — 진입 분기, AR 세션 시작/중단, 코드 채택·기각(+사유), 격자 갱신(stage·잔차·신뢰도), **상태 전이(from→to+trigger)**, 저장/대체/완료, 배너 발동. 아래 시나리오의 체크 로그는 전부 info 레벨.
- **`.debug` = 중간 컨텍스트** — 개별 인식(텍스트·conf), raycast 좌표, 격자 벡터·목표 외삽 좌표, 화살표 각도(1Hz 스로틀).
- **고빈도 데이터(기기 포즈 등)는 콘솔 미출력** — NDJSON(DR-003) 전용.
- 채널 분담: Xcode 콘솔(책상 실기기) / DR-002 오버레이 스트립(현장 실시간) / NDJSON(사후 분석·리플레이) — 같은 이벤트의 3개 창.

## 환경 구분 (중요)

| 환경 | 검증 가능 범위 |
|---|---|
| **시뮬레이터** (iPhone 17 Pro) | 수동 등록·요약 카드·영속성·수명주기·권한 거부 폴백 — **AR/카메라 불가** |
| **실기기 (LiDAR: iPhone Pro)** | 전체 — 스캔 등록·되찾기·격자·강등·디버그 오버레이 |
| **실기기 (비 LiDAR)** | raycast 성공률 비교(스파이크 2) |
| **유닛 테스트** (Swift Testing) | 파서·GridEstimator·상태 기계·리플레이 — 현장 로그 픽스처 |

## 시뮬레이터 시나리오

**S1. 수동 등록 + 영속성 (US3, FR-004/017/020)**
설정에서 카메라 권한 없음 상태 → 홈 드로어 "내 차 찾기" → 수동 폼 표시 확인 → "B2-A-3" 입력, 층 자동 인식 확인 → 저장 → 요약 카드 표시 → 앱 종료 후 재실행 → 진입 시 요약 카드 직행.
```
[ParkingFinder] entry: no-active-record, camera=denied → manual
[ParkingFinder] session saved: B2-A-3 floor=B2(code) photos=0
[ParkingFinder] entry: active-record → summary
```

**S2. 층 없는 코드 + 수명주기 (FR-005/019/021)**
"A-3" 입력 → 층 선택 시트 표시 → B2 선택 → 저장 `floor=B2(manual)` → [새 위치 등록] → 대체 확인 얼럿 → 새 코드 저장 → 이전 레코드 삭제 로그 → [찾았어요] → completed + dismiss.
```
[ParkingFinder] floor prompt shown (no floor token)
[ParkingFinder] replaced active session (old removed, photos deleted)
[ParkingFinder] session completed by=manual, retained=1
```

## 실기기 시나리오 (지하주차장)

**D1. 스캔 등록 (US1, FR-002/002a/002b/003) — SC-001 15초**
진입 → 스캔 시작 → 주변 훑기 → 자동 저장 → 요약 카드에서 목표·인접 코드·자동 사진 확인 → 오선정 시 즉시 교체.
```
[ParkingFinder] scan: observed B2-A-3 pos=(…) hit=2 → confirmed
[ParkingFinder] scan: auto-saved target=B2-A-3 neighbors=[A-4(3.1m), B-3(5.2m)] photos=2
```

**D2. 되찾기 단계 전환 (US2, FR-009) — SC-003 5초**
[안내 시작] → 코드 1개: searching 문구 → 같은 구역 2개째: axisGuidance + 화살표 → 3개째: gridGuidance → 신뢰도 변화 확인.
```
[ParkingFinder] state: searching → axisGuidance(number) obs=2
[ParkingFinder] state: axisGuidance → gridGuidance obs=3 residual=0.4m conf=medium
[ParkingFinder] guidance: arrow=37° dist=18m
```

**D3. 강등 + 복귀 (FR-012) — SC-005**
불규칙 배치(스네이크) 구간에서 잔차 초과 → 화살표 숨김 + 근접확인 모드 → 정합 관측 후 복귀.
```
[ParkingFinder] state: gridGuidance → degraded trigger=residual-exceeded(4.2m)
[ParkingFinder] state: degraded → gridGuidance (2 consistent obs)
```

**D4. 도착 + 인접 보조 (FR-013/013a) — SC-006 오채택 0**
목표 기둥 접근 → 인접 코드 목격 로그 → 목표 연속 인식 → arrived → [찾았어요].
```
[ParkingFinder] neighbor sighted: A-4 → confidence boost
[ParkingFinder] rejected: '12가3456' reason=skeleton-mismatch
[ParkingFinder] state: → arrived (target 2 consecutive)
```

**D5. 실패 경로 (FR-014/015)** — 다른 층에서 시도 → floorMismatch 배너 / 어두운 구역 → raycastFailed 누적 → anchorFailing 배너 + 손전등 토글.

**D6. 디버그 도구 (DR-001~005)**
요약 카드 경과시간 라벨 5탭 → 토글 스낵바 → AR 화면에 오버레이(인식 박스·앵커 라벨·격자·목표·잔차선·상태 스트립) → 세션 후 `Documents/ParkingLogs/*.ndjson` 생성 → DevTools에서 내보내기. 토글 off → 오버레이·기록 없음 확인.

**D7. 백그라운드 복귀** — 되찾기 중 홈 이동→복귀 → 관측 리셋 + searching 재시작 토스트, 저장 기록 유지.

## 유닛 테스트 (NavigationTests/ParkingFinder/)

- `PillarCodeParserTests`: 3 스켈레톤 파싱, 번호판 기각, 층 토큰 유무
- `GridEstimatorTests`: 1D축(동구역/동번호), 혼합축 분해불가, 3점 아핀, 잔차 강등·복귀, 도착 판정
- `ParkingReplayTests`: D2~D4 현장 로그 픽스처 리플레이 → 기록된 gridUpdated/stateTransition과 일치(SC-009)
- `ParkingSessionStoreTests`: 수명주기(active 1개·대체·완료 보관 1건)
