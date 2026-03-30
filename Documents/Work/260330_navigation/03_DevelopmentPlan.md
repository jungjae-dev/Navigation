# 네비게이션 주행 엔진 개발 계획

> 작성일: 2026-03-30
> 기반 문서: 01_Requirements.md, 02_Design.md

---

## 1. 개발 원칙

```
1. 아래에서 위로 (Foundation → Engine → Presentation)
2. 매 단계마다 시뮬레이터에서 로그로 검증
3. 검증 안 된 단계 위에 다음 단계 쌓지 않음
4. 기존 주행 코드를 먼저 삭제하고 깨끗한 상태에서 시작
5. 삭제 후 빌드가 깨지는 곳은 stub으로 대체하여 빌드 유지
```

---

## 2. 의존성 그래프

```
Step 0: 기존 코드 삭제 + stub
    ↓
Step 1: 데이터 모델 + Route 확장
    ↓
Step 2: GPSProvider (Real + Simul)
    ↓
Step 3: MapMatcher
    ↓
Step 4: RouteTracker
    ↓
Step 5: OffRouteDetector + StateManager
    ↓
Step 6: VoiceEngine + DeadReckoning
    ↓
Step 7: NavigationEngine 통합 ← 엔진 검증 완료
    ↓
Step 8: Presentation 기본 (지도 + 아바타)
    ↓
Step 9: Presentation 전체 UI
    ↓
Step 10: 음성 TTS + 재탐색
    ↓
Step 11: CarPlay 연동
    ↓
Step 12: FileGPSProvider + stub 제거 + 최종 통합
```

---

## 3. 디버깅 지원 (개발자 메뉴)

개발 단계별 검증을 위해 개발자 메뉴에 디버깅 도구를 추가한다.

### 3.1 주행 화면 디버그 오버레이

```
주행 화면 위에 반투명 오버레이로 엔진 상태를 실시간 표시

┌─────────────────────────────────────────┐
│ ManeuverBanner                          │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ [DEBUG]                             │ │
│ │ state: navigating                   │ │
│ │ gps: valid  accuracy: 5.2m         │ │
│ │ match: ✅ dist=1.2m seg=42 Δ=3.5° │ │
│ │ step: 3/15  toManeuver: 284m       │ │
│ │ remaining: 8.5km  eta: 14:32       │ │
│ │ speed: 58km/h (16.1m/s)            │ │
│ │ voice: (idle)                       │ │
│ │ DR: inactive                        │ │
│ │ fps: 60  tick: 1.002s              │ │
│ └─────────────────────────────────────┘ │
│           🗺️ 지도                        │
│              🚗 (매칭 좌표)               │
│                   ● (raw GPS — 빨간 점)  │
│ BottomBar                               │
└─────────────────────────────────────────┘
```

### 3.2 개발자 메뉴 항목

```
┌─────────────────────────────────────────────────┐
│ Location Type                                   │
│   ○ Real  ○ File → [파일 선택...]               │
├─────────────────────────────────────────────────┤
│ GPX 녹화                                         │
│   [녹화 시작]  상태: 대기                         │
├─────────────────────────────────────────────────┤
│ GPX 파일 관리                                    │
│   [파일 목록] (3개)                              │
├─────────────────────────────────────────────────┤
│ 디버그 오버레이                          [  ON ] │
│   주행 화면에 엔진 상태 실시간 표시               │
├─────────────────────────────────────────────────┤
│ Raw GPS 마커                            [  ON ] │
│   매칭 전 GPS 좌표를 빨간 점으로 지도에 표시      │
├─────────────────────────────────────────────────┤
│ 콘솔 로그 레벨                                   │
│   ○ OFF  ○ 상태변화만  ○ 매초전체               │
└─────────────────────────────────────────────────┘

테스트 시나리오 (별도 기능 불필요, 기존 모드 활용):
  - 이탈 테스트: 가상 주행에서 경로 역방향으로 출발 → 자동 이탈 → 재탐색
  - GPS 손실 테스트: 중간에 gap이 있는 GPX 파일 재생 → Dead Reckoning 동작
```

### 3.3 각 항목 용도 및 구현 시점

| 항목 | 용도 | 구현 시점 |
|------|------|----------|
| 디버그 오버레이 | 엔진 전체 상태 실시간 확인 | Step 8 (UI 기본) |
| Raw GPS 마커 | 맵매칭 전후 좌표 차이 시각적 확인 | Step 8 (UI 기본) |
| 콘솔 로그 레벨 | 개발 중 상세 로그 / 릴리즈 시 OFF | Step 2 (GPS부터 사용) |
| Simul/File 속도 컨트롤 | 주행 화면 하단에서 직접 변경 (0.5x/1x/2x/4x) | Step 8 (UI 기본) |
| 이탈 테스트 | 가상 주행 역방향 출발로 검증 (별도 구현 불필요) | Step 10 |
| GPS 손실 테스트 | gap 있는 GPX 파일 재생으로 검증 (별도 구현 불필요) | Step 12 |

### 3.4 콘솔 로그 레벨 상세

```
OFF:
  (로그 없음)

상태변화만:
  "[State] preparing → navigating"
  "[Track] ★ Step 0 → Step 1 (우회전 → 좌회전)"
  "[Voice] step=0 300m: 300미터 앞 우회전"
  "[Match] ❌ offRoute! consecutiveFailures=3"

매초전체:
  "[GPS] valid=true coord=(37.5000, 127.0000) heading=45.0 speed=16.7 accuracy=5.2"
  "[Match] matched=true coord=(37.5001, 127.0002) seg=42 dist=1.2m Δ=3.5°"
  "[Track] step=3/15 toManeuver=284m remaining=8.5km eta=14:32"
  "[State] navigating"
  "[Voice] (idle)"
  "[DR] inactive"
```

---

## Step 0: 기존 주행 코드 삭제 + stub 대체

### 삭제 대상

```
Feature/Navigation/
  NavigationViewController.swift
  NavigationViewModel.swift
  ManeuverBannerView.swift
  NavigationBottomBar.swift
  NavigationMode.swift
  PlaybackControlView.swift
  PlaybackControllable.swift

Service/Guidance/
  GuidanceEngine.swift
  OffRouteDetector.swift

Service/Voice/
  VoiceGuidanceService.swift
  GuidanceTextBuilder.swift

Service/Interpolation/
  MapInterpolator.swift
  LocationInterpolator.swift
  HeadingInterpolator.swift
  CameraInterpolator.swift

Service/TurnPointPopup/
  TurnPointPopupService.swift
  TurnPointPopupView.swift

Service/Parking/
  ParkingGuidanceService.swift

Map/
  MapCamera.swift
  Vehicle3DOverlayView.swift
```

### stub 대체 (빌드 유지)

```
깨지는 파일 3개만 수정:

1. AppCoordinator.swift
   - 프로퍼티 제거: navigationViewController, mapInterpolator, mapCamera, turnPointPopupService
   - startNavigation() → stub: print("[TODO] 새 엔진으로 교체 예정")
   - startVirtualDrive() → stub
   - startGPXPlayback() → stub
   - presentNavigationFromSession() → stub
   - cleanUpNavigationUI() → stub

2. NavigationSessionManager.swift
   - NavigationSession 구조체에서 guidanceEngine, voiceService, offRouteDetector 제거
   - startNavigation() → stub (엔진 생성 제거, 명령 발행만 유지)
   - stopNavigation() → stub

3. CarPlayNavigationHandler.swift
   - GuidanceEngine 참조 제거
   - bindGuidanceEngine() → stub
   - GuidanceTextBuilder 참조 제거
```

### 검증

```
✅ 빌드 성공
✅ 앱 실행 → 홈/검색/경로요약 정상 동작
✅ "안내 시작" 탭 → 주행 화면 안 뜸 (stub) → 크래시 없음
✅ CarPlay 연결 → 기본 화면 정상 (주행만 안 됨)
```

---

## Step 1: 데이터 모델 + Route 확장

### 구현 파일

```
Engine/Model/
  GPSData.swift
  NavigationGuide.swift
  ManeuverInfo.swift
  TurnType.swift
  VoiceCommand.swift
  NavigationState.swift
  MatchResult.swift
  DeadReckoningResult.swift

Service/LBS/Model/
  RouteStep.swift → 필드 추가 (turnType, roadName, duration)
  Route.swift → provider 필드 추가

Service/LBS/Kakao/
  KakaoModelConverter.swift → 폴리라인 분할 + turnType/roadName 저장
  KakaoRouteResponse.swift → (변경 없음, 이미 type/name 파싱)

Service/LBS/Apple/
  AppleModelConverter.swift → provider = .apple 설정
```

### 테스트 파일

```
Tests/EngineTests/
  TurnTypeTests.swift → 카카오 type 코드 → TurnType 매핑

Tests/
  KakaoModelConverterTests.swift → 폴리라인 분할 검증
```

### 검증

```
단위 테스트:
  ✅ 카카오 Route 변환 → step별 폴리라인이 구간 좌표 배열 (점 1개 아님)
  ✅ 카카오 step에 turnType, roadName 저장됨
  ✅ Apple 변환도 동일 Route 모델로 정상
  ✅ TurnType 매핑: 카카오 type 101 → .rightExit 등

시뮬레이터 로그 (실제 API 데이터로 검증):
  카카오 API 실제 호출 (서울역→강남역 등):
    "[Kakao] steps: 15, polyline points: 340, provider: kakao"
    "[Step 0] 우회전 | turnType: rightTurn(13) | roadName: 세종대로 | polyline: 34pts"
    "[Step 1] 좌회전 | turnType: leftTurn(12) | roadName: 테헤란로 | polyline: 45pts"
  Apple API 실제 호출 (동일 경로):
    "[Apple] steps: 12, polyline points: 280, provider: apple"
    "[Step 0] instructions: ??? | turnType: unknown | roadName: nil | polyline: 28pts"
    → instructions 실제 값 캡처 (한국어? 영어? 형식?)
    → turnType 추론 가능 여부 판단 → AppleModelConverter에 파싱 로직 추가 여부 결정
  ✅ 카카오: step별 폴리라인이 구간 좌표 배열 (분할 정상)
  ✅ 카카오: turnType, roadName 저장됨
  ✅ Apple: 동일 Route 모델로 정상 변환
  ✅ Apple: instructions 실제 값 확인 + turnType 추론 방식 결정
  ✅ 두 API 모두 step polyline 점이 2개 이상
```

---

## Step 2: GPSProvider (Real + Simul)

### 구현 파일

```
GPS/
  GPSProviding.swift       ← 프로토콜
  RealGPSProvider.swift    ← CoreLocation + 1초 틱 타이머
  SimulGPSProvider.swift   ← 폴리라인 위 자동 이동
```

### 검증 (시뮬레이터)

```
RealGPSProvider:
  - Xcode > Debug > Simulate Location > Freeway Drive
  - 매초 로그:
    "[GPS] valid=true coord=(37.5000, 127.0000) heading=45.0 speed=16.7 accuracy=5.0"
  - GPS 시뮬레이션 끄면:
    "[GPS] valid=false coord=(37.5000, 127.0000) ← 마지막 좌표"

SimulGPSProvider:
  - Step 1에서 만든 Route 폴리라인 전달
  - 매초 로그:
    "[SimulGPS] coord=(37.5001, 127.0001) heading=90.0 speed=13.9 segment=0"
    "[SimulGPS] coord=(37.5001, 127.0003) heading=90.0 speed=13.9 segment=1"

검증 기준:
  ✅ RealGPS: 1초마다 빠짐없이 GPSData 발행
  ✅ RealGPS: GPS 끊겼을 때 isValid=false 1초마다 발행
  ✅ SimulGPS: 폴리라인 위 좌표가 순서대로 이동
  ✅ SimulGPS: heading이 폴리라인 세그먼트 방향과 일치
```

---

## Step 3: MapMatcher

### 구현 파일

```
Engine/
  MapMatcher.swift
```

### 테스트 파일

```
Tests/EngineTests/
  MapMatcherTests.swift
```

### 검증

```
단위 테스트:
  ✅ 경로 위 좌표 → 매칭 성공, 스냅 좌표 반환
  ✅ 경로에서 60m → 매칭 실패
  ✅ 역방향 heading (자동차) → 매칭 실패
  ✅ 역방향 heading (도보) → 매칭 성공 (방향 검증 스킵)
  ✅ 저속 < 5km/h → 방향 검증 스킵
  ✅ segmentIndex가 정상 전진
  ✅ 윈도우 탐색 (±10)이 전체 탐색과 동일 결과

시뮬레이터 (SimulGPS → MapMatcher, 실제 API 경로 사용):
  - 카카오 실제 경로의 폴리라인으로 SimulGPS + MapMatcher 실행
  - Apple 실제 경로의 폴리라인으로 SimulGPS + MapMatcher 실행
  - 매초 로그:
    "[Match] matched=true coord=(37.5001, 127.0002) seg=5 dist=1.2m angle=3.5°"
  - 검증 기준:
    ✅ 카카오 경로: 매칭 성공률 100%, segmentIndex 단조 증가
    ✅ Apple 경로: 매칭 성공률 100%, segmentIndex 단조 증가
    ✅ distanceFromRoute < 5m (SimulGPS는 정확하므로)
```

---

## Step 4: RouteTracker

### 구현 파일

```
Engine/
  RouteTracker.swift
```

### 테스트 파일

```
Tests/EngineTests/
  RouteTrackerTests.swift
```

### 검증

```
단위 테스트:
  ✅ 안내 포인트 30m 이내 → 스텝 전진
  ✅ 안내 포인트 31m → 스텝 유지
  ✅ 남은 거리 계산 정확성 (±10m 오차 허용)
  ✅ 마지막 스텝 이후 처리 (index out of bounds 없음)
  ✅ 남은 시간 (카카오): step별 duration 합산
  ✅ 남은 시간 (Apple): expectedTravelTime × (remainingDistance / totalDistance)
  ✅ ETA 계산

시뮬레이터 (SimulGPS → MapMatcher → RouteTracker, 실제 API 경로 사용):
  - 카카오/Apple 실제 경로 각각으로 검증
  - 매초 로그:
    "[Track] step=0/15 distToManeuver=450m remaining=12.5km eta=14:32"
  - 스텝 전진 시:
    "[Track] ★ Step 0 → Step 1 (우회전 → 좌회전)"
  - 검증 기준:
    ✅ 카카오 경로: 모든 스텝 순서대로 전진
    ✅ Apple 경로: 모든 스텝 순서대로 전진
    ✅ remainingDistance 단조 감소
    ✅ 마지막 스텝 도달 시 remainingDistance ≈ 0
```

---

## Step 5: OffRouteDetector + StateManager

### 구현 파일

```
Engine/
  OffRouteDetector.swift
  StateManager.swift
```

### 테스트 파일

```
Tests/EngineTests/
  OffRouteDetectorTests.swift
  StateManagerTests.swift
```

### 검증

```
단위 테스트 (OffRouteDetector):
  ✅ 매칭 실패 2회 → isOffRoute: false
  ✅ 매칭 실패 3회 → isOffRoute: true
  ✅ 중간에 매칭 성공 → 카운터 리셋
  ✅ 출발 5초 이내 → 보류 (false)
  ✅ 출발 35m 이내 → 보류 (false)
  ✅ GPS 정확도 > 120m → 보류 (false)
  ✅ reset() 후 카운터 0

단위 테스트 (StateManager):
  ✅ preparing → navigating (첫 매칭 성공)
  ✅ navigating → arrived (30m 이내)
  ✅ navigating → rerouting (이탈 확정)
  ✅ navigating → stopped (사용자 종료)
  ✅ rerouting → navigating (새 경로 수신)
  ✅ rerouting → arrived (재탐색 중 도착)
  ✅ arrived → stopped (5초 or 버튼)

시뮬레이터 (SimulGPS → 전체 체인, 실제 API 경로 사용):
  - 카카오/Apple 실제 경로 각각으로 검증
  - 상태 전이 로그:
    "[State] preparing → navigating"
    ... (주행 중) ...
    "[State] navigating → arrived"
  - 검증 기준:
    ✅ 카카오 경로: 정상 주행 시 이탈 판정 안 됨 + 도착 전이
    ✅ Apple 경로: 정상 주행 시 이탈 판정 안 됨 + 도착 전이
```

---

## Step 6: VoiceEngine + DeadReckoning

### 구현 파일

```
Engine/
  VoiceEngine.swift
  DeadReckoning.swift
```

### 테스트 파일

```
Tests/EngineTests/
  VoiceEngineTests.swift
  DeadReckoningTests.swift
```

### 검증

```
단위 테스트 (VoiceEngine):
  ✅ 초기 안내: "경로 안내를 시작합니다"
  ✅ 1200m 트리거 (일반도로)
  ✅ 300m / 120m 트리거 (일반도로)
  ✅ 500m / 200m 트리거 (고속도로, speed > 80km/h)
  ✅ 중복 방지: 같은 step+band 재트리거 안 됨
  ✅ 짧은 스텝(100m): 1200m/300m 스킵, 120m 밴드로 즉시 안내
  ✅ 스텝 전진 시 이전 step 항목 정리

단위 테스트 (DeadReckoning):
  ✅ 80km/h × 1초 = 22.2m 전진
  ✅ 80km/h × 3초 = 66.6m 전진
  ✅ 세그먼트 경계 넘는 전진 (polyline[43]→[44]→[45])
  ✅ 추정 좌표가 폴리라인 위에 있음
  ✅ heading = 전진한 세그먼트 방향
  ✅ segmentIndex 정상 갱신

시뮬레이터 (SimulGPS → 전체 체인, 실제 API 경로 사용):
  - 카카오 경로: turnType + roadName 기반 텍스트 생성 확인
    "[Voice] initial: 경로 안내를 시작합니다"
    "[Voice] step=0 1200m: 세종대로 방면 우회전입니다"  ← roadName 사용
    "[Voice] step=0 300m: 300미터 앞 우회전"            ← turnType 사용
    "[Voice] step=0 120m: 전방 우회전"
  - Apple 경로: instructions 텍스트 기반 확인
    "[Voice] step=0 1200m: Turn right onto Sejong-daero"  ← 원본 텍스트
    "[Voice] step=0 300m: 300미터 앞, Turn right"
  - 검증 기준:
    ✅ 카카오: 각 스텝마다 최소 1회 음성 트리거 + roadName 포함
    ✅ Apple: 각 스텝마다 최소 1회 음성 트리거 + 원본 텍스트 활용
    ✅ 같은 밴드 중복 안 됨
```

---

## Step 7: NavigationEngine 통합 ★ (엔진 검증 완료)

### 구현 파일

```
Engine/
  NavigationEngine.swift    ← 조합기

Service/CarPlay/
  NavigationSessionManager.swift  ← 재설계 (stub → 실제 구현)
```

### 검증 (시뮬레이터 — 가장 중요한 단계)

```
SimulGPSProvider → NavigationEngine → guidePublisher 구독 → 콘솔 로그

매초 NavigationGuide 전체 로그:
  "[Guide] state=navigating"
  "[Guide] maneuver: 우회전 300m (테헤란로) icon=arrow.turn.up.right"
  "[Guide] next: 좌회전 1.2km"
  "[Guide] remaining: 12.5km 18분 eta=14:32"
  "[Guide] position: (37.5001, 127.0002) heading=90.0 speed=13.9"
  "[Guide] gps=valid voice=nil"

전체 경로 주행 시:
  "[State] preparing → navigating"
  "[Voice] initial: 경로 안내를 시작합니다"
  "[Track] step=0 distToManeuver=1200m"
  "[Voice] step=0 1200m: 테헤란로 방면 우회전입니다"
  ...
  "[Track] ★ Step 0 → Step 1"
  ...
  "[Track] ★ Step 11 → Step 12 (마지막)"
  "[State] navigating → arrived"
  "[Voice] 목적지에 도착했습니다"

카카오 실제 경로로 전체 주행:
  ✅ 출발~도착 전체 시나리오 정상 완료
  ✅ 모든 스텝 전진 + 음성 트리거 (turnType + roadName 기반)
  ✅ preparing → navigating → arrived 전이
  ✅ remainingDistance 단조 감소
  ✅ matchedPosition이 폴리라인 위

Apple 실제 경로로 전체 주행:
  ✅ 출발~도착 전체 시나리오 정상 완료
  ✅ 모든 스텝 전진 + 음성 트리거 (instructions 기반)
  ✅ preparing → navigating → arrived 전이
  ✅ remainingDistance 단조 감소
  ✅ matchedPosition이 폴리라인 위

두 API 공통:
  ✅ 모든 컴포넌트 연동 확인 (로그로)
  ✅ 엔진이 provider를 구분하여 올바른 텍스트 생성
```

---

## Step 8: Presentation 기본 (지도 + 아바타 + 폴리라인)

### 구현 파일

```
Feature/Navigation/
  NavigationViewController.swift  ← 기본 골격
  Helper/
    LocationInterpolator.swift    ← 60fps 보간
    NavigationCameraHelper.swift  ← 카메라 고도/피치
```

### 검증 (시뮬레이터 — 시각적 확인)

```
SimulGPSProvider → NavigationEngine → NavigationViewController

  ✅ 지도에 경로 폴리라인 표시
  ✅ 출발지/목적지 마커 표시
  ✅ 아바타가 경로 위를 부드럽게 이동 (60fps, 끊김 없음)
  ✅ 카메라가 아바타를 따라감
  ✅ 속도에 따라 카메라 줌 변화
  ✅ 도착 시 이동 멈춤
  ✅ 화면 꺼짐 방지 동작 확인

AppCoordinator stub 연결:
  - startNavigation() stub → 실제 NavigationViewController 생성으로 교체
  - 경로요약 → "안내 시작" → 주행 화면 진입 확인

백그라운드 처리:
  - 주행 시작 시 Background Location + Audio 모드 활성화
  - 주행 종료 시 LocationService stop 처리
  - isIdleTimerDisabled = true (앱 시작 시 설정, AppDelegate에서)
```

---

## Step 9: Presentation 전체 UI

### 구현 파일

```
Common/UI/DesignSystem/
  Theme+Navigation.swift          ← 주행 화면 전용 디자인 토큰 (다크모드 포함)

Feature/Navigation/
  View/
    ManeuverBannerView.swift     ← SwiftUI (Theme+Navigation 색상 사용)
    NavigationBottomBar.swift    ← SwiftUI
    SpeedometerView.swift        ← SwiftUI
    ArrivalPopupView.swift       ← SwiftUI
    RouteOverviewButton.swift    ← SwiftUI (경로 전체 보기 버튼)
  Formatter/
    UnitFormatter.swift          ← 거리/속도 단위 포맷 (시스템/미터법/야드법)
  NavigationViewController.swift ← UI 요소 통합
```

### Theme+Navigation.swift (디자인 시스템 확장)

```
기존 Theme 구조를 확장하여 주행 화면 전용 토큰 정의:

Theme.Navigation.Colors:
  routePolyline       ← light: .systemBlue / dark: .systemCyan
  routePolylineStroke ← light: .systemBlue.opacity(0.3) / dark: .systemCyan.opacity(0.3)
  maneuverBackground  ← light: .white.opacity(0.95) / dark: .black.opacity(0.85)
  bottomBarBackground ← light: .white / dark: Color(.systemGray6)
  speedometerText     ← light: .black / dark: .white
  arrivalPopupBg      ← light: .white / dark: Color(.systemGray5)
  gpsWarningIcon      ← .systemOrange
  rerouteBanner       ← .systemYellow.opacity(0.9)

Theme.Navigation.Fonts:
  maneuverDistance     ← 기존 Theme.Fonts.maneuverDistance 활용
  maneuverInstruction ← 기존 Theme.Fonts.maneuverInstruction 활용
  nextManeuver        ← .subheadline
  speedValue          ← .monospacedDigit, 32pt, bold
  speedUnit           ← .caption
  etaValue            ← 기존 Theme.Fonts.eta 활용

Theme.Navigation.Sizes:
  maneuverIconSize    ← 36pt
  bannerHeight        ← 100pt
  bottomBarHeight     ← 80pt
  speedometerSize     ← 70pt
  buttonSize          ← 44pt

→ 모든 주행 UI가 Theme을 참조하여 다크모드 자동 대응
→ 색상/크기 변경 시 Theme만 수정하면 전체 반영
```

### 검증 (시뮬레이터)

```
  ✅ ManeuverBanner: 회전 아이콘 + 거리 + 안내문 + 도로명 + next 안내
  ✅ BottomBar: 목적지명 + ETA + 남은 거리 + 시간 + 종료 버튼
  ✅ 속도계: 현재 속도 표시, 값 변화
  ✅ GPS 아이콘: (SimulGPS에서는 항상 valid → 표시 안 됨 → OK)
  ✅ 리센터: 지도 터치 → 버튼 표시 → 7초 후 복귀 → 버튼 숨김
  ✅ 리센터: 버튼 탭 → 즉시 복귀
  ✅ 추적 해제 시: 안내 UI 유지, 지도만 자유 조작
  ✅ 경로 전체 보기: 버튼 탭 → 줌아웃 → 전체 경로 보임 → 리센터/7초 복귀
  ✅ 도착 팝업: 표시 + 5초 카운트다운 → 자동 종료 → 홈 복귀
  ✅ 다크모드: 시스템 전환 시 모든 UI 요소 색상 정상 전환
     - ManeuverBanner 배경/텍스트
     - BottomBar 배경/텍스트
     - 경로 폴리라인 색상
     - 속도계
     - 마커/아바타
  ✅ "안내 종료" 버튼 → 주행 종료 → 홈 복귀
  ✅ 단위 설정: 시스템/미터법/야드법 전환 시 거리/속도 표시 변경
     - 미터법: 300m, 12.5km, 58km/h
     - 야드법: 1000ft, 7.8mi, 36mph
```

---

## Step 10: 음성 TTS + 재탐색

### 구현 파일

```
Voice/
  VoiceTTSPlayer.swift          ← TTS 재생 + 큐
  GuidanceTextBuilder.swift     ← 카카오/Apple 텍스트 분기

Engine/
  NavigationEngine.swift        ← 재탐색 로직 추가 (API 호출 + 리셋 + 3회 재시도)
```

### 검증 (시뮬레이터)

```
음성:
  ✅ 적절한 타이밍에 한국어 음성 재생
  ✅ 음소거 토글: 탭 → 즉시 음성 중단 + 이후 무음
  ✅ 큐 방식: 음성 겹치지 않고 순서대로

재탐색 (수동):
  ✅ 재탐색 버튼 탭 → "경로를 재탐색 중입니다" 배너 + 음성
  ✅ 재탐색 성공 → 새 폴리라인 표시 + 배너 숨김
  ✅ BottomBar: 재탐색 중 "--" → 성공 후 새 거리/시간

재탐색 (자동 — 시뮬레이터에서 이탈 테스트 어려움):
  → 단위 테스트로 검증 (Step 5에서 완료)
  → 실기기 또는 FileGPSProvider로 추후 검증
```

---

## Step 11: CarPlay 연동

### 구현 파일

```
Feature/CarPlay/
  CarPlayNavigationHandler.swift  ← stub → 새 엔진 연결

App/
  CarPlaySceneDelegate.swift      ← 양방향 동기화 수정
```

### 검증 (CarPlay 시뮬레이터)

```
  ✅ iPhone "안내 시작" → CarPlay 자동 주행 화면
  ✅ CarPlay "출발" → iPhone 자동 주행 화면
  ✅ CPManeuver: 회전 아이콘 + 안내문 + 거리
  ✅ 남은 거리/시간 갱신
  ✅ 도착 → session.finishTrip()
  ✅ CarPlay 연결 해제 → 엔진 계속 동작 (iPhone만)
  ✅ CarPlay 재연결 → 현재 상태 즉시 반영
```

---

## Step 12: FileGPSProvider + stub 제거 + 최종 통합

### 구현 파일

```
GPS/
  FileGPSProvider.swift          ← GPXSimulator 래핑

Feature/DevTools/
  DevToolsViewController.swift   ← Location Type 선택 UI 수정
  DevToolsViewModel.swift        ← File 모드 연동
```

### 최종 정리

```
- AppCoordinator: 나머지 stub 제거, 모든 주행 플로우 새 코드 연결
  → startNavigation(): 완전 구현
  → startVirtualDrive(): SimulGPSProvider 연결 (경로요약 "가상 주행")
  → startGPXPlayback(): FileGPSProvider 연결 (개발자 메뉴 File 모드)
- 사용하지 않는 import/참조 정리
- 빌드 경고 해결
```

### 최종 검증

```
전체 앱 플로우:
  ✅ 홈 → 검색 → POI → 경로요약 → "안내 시작" → 주행 → 도착 → 홈
  ✅ 홈 → 즐겨찾기 → 경로요약 → "가상 주행" → 주행 → 도착 → 홈
  ✅ 개발자 메뉴 → File 선택 → 경로요약 → "안내 시작" → GPX 재생 주행
  ✅ 개발자 메뉴 → GPX 녹화 시작 → 실 주행 → 녹화 중지 → 파일 저장
  ✅ CarPlay 양방향 동기화

시나리오별 최종 확인:
  ✅ 정상 주행 (출발~도착)
  ✅ 음성 안내 (타이밍, 한국어, 음소거)
  ✅ 지도 조작 (리센터, 7초 복귀, 경로 전체 보기)
  ✅ 재탐색 (수동)
  ✅ 도착 팝업 + 5초 자동 종료
  ✅ 백그라운드 → 포그라운드 (아바타 점프 없음)
  ✅ 다크모드
```

---

## 4. 단계별 산출물 요약

| Step | 구현 | 테스트 | 검증 방법 | 디버깅 도구 |
|------|------|--------|----------|------------|
| 0 | 기존 코드 삭제 + stub | - | 빌드 성공 + 앱 실행 | - |
| 1 | 데이터 모델 + Route 확장 + 카카오 변환 | TurnTypeTests, KakaoConverterTests | 단위 테스트 + 실제 API 로그 | - |
| 2 | GPSProviding + RealGPS + SimulGPS | - | 시뮬레이터 로그 | 콘솔 로그 레벨 |
| 3 | MapMatcher | MapMatcherTests | 단위 테스트 + 실제 API 경로 로그 | 콘솔 로그 |
| 4 | RouteTracker | RouteTrackerTests | 단위 테스트 + 실제 API 경로 로그 | 콘솔 로그 |
| 5 | OffRouteDetector + StateManager | OffRouteTests, StateTests | 단위 테스트 + 실제 API 경로 로그 | 콘솔 로그 |
| 6 | VoiceEngine + DeadReckoning | VoiceTests, DRTests | 단위 테스트 + 실제 API 경로 로그 | 콘솔 로그 |
| 7 | NavigationEngine + SessionManager | - | **카카오/Apple 실제 경로 전체 주행 로그** | 콘솔 로그 (매초전체) |
| 8 | NavigationVC + 보간기 + 카메라 | - | 시뮬레이터 시각적 확인 | 디버그 오버레이, Raw GPS 마커, Simul/File 속도 컨트롤 |
| 9 | SwiftUI 뷰 4개 + UI 통합 | - | 시뮬레이터 시각적 확인 | 디버그 오버레이 |
| 10 | VoiceTTSPlayer + TextBuilder + 재탐색 | - | 시뮬레이터 음성 + 시각 + 역방향 이탈 테스트 | 디버그 오버레이 |
| 11 | CarPlay 연동 수정 | - | CarPlay 시뮬레이터 | 디버그 오버레이 |
| 12 | FileGPS + stub 제거 + 최종 통합 | - | **전체 앱 플로우 검증** | 전체 도구 활용 |
