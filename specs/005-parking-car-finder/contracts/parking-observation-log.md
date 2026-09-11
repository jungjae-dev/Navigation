# Log Contract — 관측 이벤트 NDJSON (DR-003)

파일: `Documents/ParkingLogs/parking-<yyyyMMdd-HHmmss>-<mode>.ndjson` — 한 줄 = 한 이벤트(JSON). `LocationRecorder` NDJSON 패턴 준용. 카메라 영상·이미지 미포함(지각 계층 비기록).

공통 필드: `{"t": <초, 세션 시작 기준 상대시각>, "e": "<이벤트 타입>", ...}`

| e | 페이로드 | 목적 |
|---|---|---|
| `sessionStart` | `mode`(scan/find), `target`(find 시 코드·토큰·skeleton), `neighbors`, `device`(기종·LiDAR 여부) | 리플레이 초기 조건 |
| `codeObserved` | `raw`, `parsed{floor,zone,zoneIdx,num}`, `pos[x,y,z]?`(raycast 실패 시 null), `conf`, `hit`(누적 횟수) | 핀 꽂기 재현 |
| `candidateRejected` | `raw`, `reason`(skeleton-mismatch/low-conf/…) | 필터 검증(FR-008) |
| `raycastFailed` | `raw`, `consecutive` | 지각 실패 진단(FR-015) |
| `trackingChanged` | `state`(normal/limited), `reason?` | 환경 진단 |
| `devicePose` | `pos[x,y,z]`, `heading[x,z]` (1Hz 스로틀) | 화살표 각도 재계산 |
| `gridUpdated` | `stage`, `origin`, `rowVec`, `colVec`, `residualRMS`, `targetEst[x,z]?`, `confidence` | 피팅 재현 |
| `guidanceShown` | `state`, `arrowDeg?`, `distanceM?`, `confidence` | 표시값 vs 재계산 대조(추정 vs 렌더 버그 구분) |
| `stateTransition` | `from`, `to`, `trigger`(예: residual-exceeded 3.4m) | 상태 기계 검증(DR-004와 동일 지점) |
| `arrivalConfirmed` / `sessionEnd` | `by`(target-recognition/manual), `elapsed` | 종료 |

**리플레이 계약**: `ParkingEventReplayer`는 `codeObserved`/`devicePose` 스트림만 입력으로 `gridUpdated`·`stateTransition`·`guidanceShown`(각도) 시퀀스를 재계산할 수 있어야 하며, 로그에 기록된 값과 일치해야 한다(불일치 = 로직 회귀 또는 렌더 버그). 유닛 테스트는 실제 현장 로그 파일을 픽스처로 사용.

좌표는 세션 월드 좌표계(중력 정렬, 세션 한정) — 파일 안에서 자기완결적. 프라이버시: 코드 문자열·상대 좌표만 포함, 위치(GPS)·영상 없음.
