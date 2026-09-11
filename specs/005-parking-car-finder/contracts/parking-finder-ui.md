# UI Contract — ParkingFinder 모듈

허브-스포크 구조(스펙 Clarifications Q1). 진입: `AppCoordinator.showParkingFinder()` — `UINavigationController` 풀스크린 present.

## 진입 분기 (coordinator)

| 조건 | 첫 화면 |
|---|---|
| 활성 기록 없음 + 카메라 허용 | ParkingAR(.scan) |
| 활성 기록 없음 + 카메라 거부/미결정→거부 | ManualEntry |
| 활성 기록 있음 | Summary (허브) |

## 화면 계약

### ParkingSummaryViewController (허브 = 폴백 FR-016/001a)

표시: 목표 코드(최대 강조) · 층 + "N시간 전 주차" + 정확 시각 · 사진(탭→PhotoViewer) · 저장 직후엔 "저장되었습니다" + 함께 인식된 코드 목록(목표 즉시 교체 UI, FR-002a).
액션: `[안내 시작]`→ParkingAR(.find) (권한 거부 시 설정 안내 시트) · `[✓ 찾았어요]`→완료 처리→dismiss→홈 · `[새 위치 등록]`→대체 확인 얼럿(FR-019)→ParkingAR(.scan).
히든: 경과시간 라벨 5회 탭 → 디버그 토글(DR-005) 스낵바 표시.

### ParkingARViewController (mode: .scan | .find — 공용 AR 화면)

공통: ARView 풀스크린, 상단 닫기/뒤로, 하단 `[🔦 손전등]` `[⌨ 직접 입력](.scan만)` `[사진](.find만)`. 트래킹/앵커 실패 배너. 디버그 활성 시 오버레이 레이어(디버그 계약 아래). 상단 안내 문구 5회 탭 = 디버그 토글(허브 제스처와 동일 — 첫 등록처럼 Summary를 거치지 않는 흐름 대응).

**.scan (등록)**:
- 안내 문구: "주변 기둥의 위치 표지판을 비춰주세요"
- 코드 확보 진행 칩(인식된 코드 나열), 신뢰 코드 1개 확보 + 3초 경과 시 자동 저장(FR-002) → Summary로 교체(back 스택 제거)
  - 3초 유예의 목적: 동일 텍스트 2회 관측 확정(R4 오인식 완화) + 최근접 선정(FR-002a)이 첫 코드 하나로 성급히 확정되는 것 방지. **인접 코드 수집 대기가 아님**(FR-002)
  - 위치 파악 실패 코드만 확보된 경우에도 저장 진행 — 목표=최다 관측 코드(FR-002a), 인접 거리 생략
- 15초 무확보 → "직접 입력할까요?" 배너(FR-004) → ManualEntry
- 층 토큰 없음 → 저장 직전 층 선택 시트(FR-005: B1~B5 + 기타 + 모름)

**.find (되찾기)** — HUD는 GuidanceState의 순수 함수(FR-010):

| GuidanceState | HUD |
|---|---|
| searching | "주변 기둥을 비춰주세요" + 읽힌 코드 칩 |
| needMoreObservation(axis) | 부족한 축 특정 문구 ("같은 구역의 다른 번호 기둥을…") |
| axisGuidance / gridGuidance | 2D 회전 화살표 + "~Nm 이 방향" + 신뢰도 점(●●○) + 단계 라벨 |
| degraded | 화살표 숨김 + "번호 배치가 불규칙합니다. 주변 기둥에서 {목표} 를 직접 확인하세요" + 사진 썸네일. 목표에 번호가 있으면 그라디언트 힌트 병기: "번호가 작아지는 쪽으로 (지금 27 → 목표 9)" / "가까워지고 있어요" / "반대 방향이에요" — 새 확정 관측마다 갱신 (FR-012) |
| arrived | 도착 확정 풀오버레이 + `[✓ 찾았어요]`(완료→dismiss) |

파싱 불가 세션(FR-016): degraded 고정 진입 — "주변 기둥에서 {목표} 를 직접 확인하세요" + 층 상기 + 사진. 화살표·격자 관련 UI 미노출.

배너(직교): floorMismatch("{저장층}로 이동하세요" / 층 미상 코드면 "{저장층}에 주차하셨습니다"), trackingLimited("천천히 움직여주세요"), anchorFailing("기둥에 더 가까이 가거나 손전등을 켜보세요").

### ParkingManualEntryViewController (폴백 FR-004/017)

코드 텍스트필드 + 층 선택 + 사진 첨부(선택, 권한 허용 시) + `[저장]`→Summary. 권한 거부 시 이 화면이 등록 기본. `[📷 촬영으로 인식]` → 권한 있으면 .scan, 없으면 설정 안내.

### ParkingPhotoViewerViewController

핀치줌 사진 뷰어. Summary·AR(.find)에서 진입.

## 공통 규칙

- 미저장 이탈(.scan/Manual 입력 중 ✕): 확인 얼럿 1회 (스펙 엣지)
- 백그라운드 복귀(.find): 관측 무효화 → searching 재시작 토스트 (스펙 엣지)
- 비AR UI(Summary/Manual/버튼)는 `Theme` 토큰 준수, WCAG AA (design 원칙)
- 홈 진입점: `HomeDrawerViewController`에 "내 차 찾기" 버튼(주차 아이콘) — 액티브 기록 있으면 뱃지/부제("B2-A-3 · 3시간 전")

## 디버그 오버레이 계약 (DR-001/002/005)

토글: DevToolsSettings.parkingDebugEnabled (DevTools 메뉴 행 + 허브 히든 제스처). off 시 어떤 디버그 객체도 생성 안 됨.

| 요소 | 형태 |
|---|---|
| 인식 박스 | 화면 좌표 사각형 — 채택 초록 / 기각 빨강+사유 짧은 라벨 |
| 코드 앵커 | RealityKit 빌보드 텍스트 라벨(신뢰도 색: 2회+ 흰색, 1회 노랑) |
| 격자 | 원점에서 행/열 축 화살표 + 외삽 격자점(예측 인덱스 라벨) 고스트 |
| 목표 예측 | 강조 마커(가상 핀) |
| 잔차 | 예측→관측 위치 연결선 (길이=잔차) |
| 궤적 | devicePose 폴리라인 |
| 상태 스트립(상단 1줄) | `상태 · 관측 n(유효 m) · 잔차 x.xm · 신뢰 z` + 최근 기각 사유 |
| ARKit 내장 | debugOptions 토글(특징점·원점) — 스트립 롱프레스로 on/off |

레코딩(DR-003): 디버그 활성 중 자동 기록 → `Documents/ParkingLogs/`. DevTools 파일 목록에서 공유 내보내기.
