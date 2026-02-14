# Navigation App - Architecture Design

## 1. 아키텍처 패턴: MVVM + Coordinator

SwiftUI 중심의 MVVM 패턴에 Coordinator를 결합하여 화면 전환을 관리한다.

```
┌──────────────────────────────────────────────────────────┐
│                      App Layer                           │
│  NavigationApp (SwiftUI App) + CarPlay SceneDelegate     │
├──────────────────────────────────────────────────────────┤
│                   Coordinator Layer                       │
│  AppCoordinator → NavigationCoordinator                  │
│                 → SearchCoordinator                       │
│                 → CarPlayCoordinator                      │
├──────────────────────────────────────────────────────────┤
│                    View Layer (SwiftUI)                   │
│  HomeView │ SearchView │ RoutePreviewView │ NavigationView│
├──────────────────────────────────────────────────────────┤
│                  ViewModel Layer                          │
│  HomeVM │ SearchVM │ RoutePreviewVM │ NavigationVM        │
├──────────────────────────────────────────────────────────┤
│                   Service Layer                           │
│  LocationService │ RouteService │ SearchService           │
│  GuidanceEngine  │ VoiceService │ CarPlayService          │
│  VehicleIconService │ VirtualDriveEngine │ GPSRecorder    │
│  MapInterpolator │ TurnPointPopupService                  │
├──────────────────────────────────────────────────────────┤
│                    Data Layer                             │
│  SwiftData (FavoritePlace, SearchHistory, NavRecord)      │
├──────────────────────────────────────────────────────────┤
│                 Apple Frameworks                          │
│  MapKit │ CoreLocation │ AVFoundation │ CarPlay │ Combine │
└──────────────────────────────────────────────────────────┘
```

---

## 2. 프로젝트 폴더 구조

```
Navigation/
├── Navigation/
│   ├── App/
│   │   ├── NavigationApp.swift              # @main SwiftUI App
│   │   ├── AppDelegate.swift                # UIKit lifecycle (CarPlay 등록)
│   │   └── SceneDelegate.swift              # CarPlay Scene 처리
│   │
│   ├── Coordinator/
│   │   ├── AppCoordinator.swift             # 루트 네비게이션 관리
│   │   ├── NavigationCoordinator.swift      # 안내 화면 플로우
│   │   └── SearchCoordinator.swift          # 검색 플로우
│   │
│   ├── Feature/
│   │   ├── Home/
│   │   │   ├── HomeView.swift               # 메인 화면 (지도 + 검색바)
│   │   │   └── HomeViewModel.swift
│   │   │
│   │   ├── Search/
│   │   │   ├── SearchView.swift             # 검색 자동완성 화면 (키보드 활성)
│   │   │   ├── SearchViewModel.swift
│   │   │   ├── SearchResultRow.swift        # 검색 결과 행
│   │   │   ├── RecentSearchView.swift       # 최근 검색 목록
│   │   │   ├── SearchResultDrawer.swift     # 검색 결과 드로어 (Bottom Sheet)
│   │   │   ├── SearchResultMapOverlay.swift # 검색 결과 마커 관리
│   │   │   └── DrawerListFocusTracker.swift # 드로어 스크롤 ↔ 지도 포커스 연동
│   │   │
│   │   ├── RoutePreview/
│   │   │   ├── RoutePreviewView.swift       # 경로 미리보기
│   │   │   ├── RoutePreviewViewModel.swift
│   │   │   └── RouteOptionRow.swift         # 경로 옵션 행
│   │   │
│   │   ├── Navigation/
│   │   │   ├── NavigationView.swift         # 안내 화면
│   │   │   ├── NavigationViewModel.swift
│   │   │   ├── ManeuverBanner.swift         # 상단 회전 안내 배너
│   │   │   └── NavigationBottomBar.swift    # 하단 정보 바
│   │   │
│   │   ├── Favorites/
│   │   │   ├── FavoritesView.swift          # 즐겨찾기 관리
│   │   │   └── FavoritesViewModel.swift
│   │   │
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift           # 설정 화면
│   │   │   └── SettingsViewModel.swift
│   │   │
│   │   ├── VirtualDrive/
│   │   │   ├── VirtualDriveView.swift       # 가상 주행 화면
│   │   │   └── VirtualDriveViewModel.swift
│   │   │
│   │   ├── VehicleIconSettings/
│   │   │   ├── VehicleIconSettingsView.swift # 차량 아이콘 설정 화면
│   │   │   ├── VehicleIconSettingsViewModel.swift
│   │   │   ├── LiftSubjectView.swift        # 배경 제거 편집 화면
│   │   │   └── Model3DPreviewView.swift     # 3D 모델 미리보기
│   │   │
│   │   └── DevTools/
│   │       ├── DevToolsView.swift           # 개발자 메뉴
│   │       ├── DevToolsViewModel.swift
│   │       ├── GPXRecorderView.swift        # GPS 녹화 컨트롤
│   │       └── GPXPlayerView.swift          # GPS 재생 컨트롤
│   │
│   ├── Map/
│   │   ├── MapView.swift                    # MKMapView의 UIViewRepresentable 래퍼
│   │   ├── MapViewController.swift          # MKMapView 직접 제어
│   │   ├── MapCamera.swift                  # 카메라 추적 로직
│   │   ├── Overlay/
│   │   │   ├── RouteOverlay.swift           # 경로 폴리라인 오버레이
│   │   │   ├── RouteOverlayRenderer.swift   # 경로 렌더러 (색상, 두께)
│   │   │   └── LocationMarker.swift         # 현재 위치 마커
│   │   └── Annotation/
│   │       ├── DestinationAnnotation.swift  # 목적지 핀
│   │       └── WaypointAnnotation.swift     # 경유지 핀 (Phase 2)
│   │
│   ├── Service/
│   │   ├── Location/
│   │   │   ├── LocationService.swift        # CLLocationManager 래퍼
│   │   │   └── GeofenceManager.swift        # 지오펜스 관리
│   │   │
│   │   ├── Route/
│   │   │   ├── RouteService.swift           # MKDirections 래퍼 (경로 탐색)
│   │   │   └── RouteModels.swift            # 경로 관련 모델
│   │   │
│   │   ├── Search/
│   │   │   ├── SearchService.swift          # MKLocalSearch 래퍼
│   │   │   └── GeocodingService.swift       # CLGeocoder 래퍼
│   │   │
│   │   ├── Guidance/
│   │   │   ├── GuidanceEngine.swift         # 안내 타이밍 핵심 엔진
│   │   │   ├── OffRouteDetector.swift       # 경로 이탈 감지
│   │   │   ├── StepTracker.swift            # 현재 스텝 추적
│   │   │   └── RerouteManager.swift         # 재경로 탐색 관리
│   │   │
│   │   ├── Voice/
│   │   │   ├── VoiceGuidanceService.swift   # AVSpeechSynthesizer 래퍼
│   │   │   └── GuidanceTextBuilder.swift    # 안내 텍스트 생성
│   │   │
│   │   ├── CarPlay/
│   │   │   ├── CarPlayService.swift         # CarPlay 템플릿 관리
│   │   │   ├── CarPlayMapManager.swift      # CarPlay 지도 제어
│   │   │   └── CarPlaySearchHandler.swift   # CarPlay 검색 처리
│   │   │
│   │   ├── VehicleIcon/
│   │   │   ├── VehicleIconService.swift     # 차량 아이콘 관리 (프리셋/커스텀)
│   │   │   ├── LiftSubjectProcessor.swift   # Vision 배경 제거 처리
│   │   │   ├── Vehicle3DRenderer.swift      # SceneKit 3D 차량 렌더링
│   │   │   └── VehicleIconView.swift        # 차량 아이콘 SwiftUI 뷰
│   │   │
│   │   ├── VirtualDrive/
│   │   │   ├── VirtualDriveEngine.swift     # 가상 주행 시뮬레이션 엔진
│   │   │   ├── VirtualLocationProvider.swift # 가상 위치 생성기
│   │   │   └── VirtualDriveController.swift  # 재생/일시정지/시크 컨트롤
│   │   │
│   │   ├── GPXRecorder/
│   │   │   ├── GPXRecorder.swift            # GPS 경로 녹화
│   │   │   ├── GPXPlayer.swift              # GPX 파일 재생
│   │   │   ├── GPXParser.swift              # GPX XML 파싱
│   │   │   └── GPXFileManager.swift         # GPX 파일 저장/로드/관리
│   │   │
│   │   ├── Interpolation/
│   │   │   ├── MapInterpolator.swift        # CADisplayLink 기반 프레임 보간 관리
│   │   │   ├── LocationInterpolator.swift   # 위치 좌표 선형 보간
│   │   │   ├── HeadingInterpolator.swift    # 방향 각도 최단경로 보간
│   │   │   └── CameraInterpolator.swift     # 지도 카메라 보간
│   │   │
│   │   └── TurnPointPopup/
│   │       ├── TurnPointPopupService.swift  # 회전 지점 접근 감지 + 팝업 트리거
│   │       ├── TurnPointPopupMapView.swift  # 팝업용 정북 2D MKMapView
│   │       └── TurnPointPopupOverlay.swift  # 팝업 UI (위치, 크기, 애니메이션)
│   │
│   ├── Model/
│   │   ├── FavoritePlace.swift              # @Model 즐겨찾기
│   │   ├── SearchHistory.swift              # @Model 검색 기록
│   │   ├── NavigationRecord.swift           # @Model 안내 기록
│   │   ├── VehicleIcon.swift                # @Model 차량 아이콘 설정
│   │   ├── GPXRecording.swift               # @Model GPS 녹화 기록
│   │   └── TransportMode.swift              # 이동 수단 enum
│   │
│   ├── Common/
│   │   ├── Extension/
│   │   │   ├── CLLocation+Extension.swift   # 위치 유틸리티
│   │   │   ├── MKMapView+Extension.swift    # 맵뷰 유틸리티
│   │   │   ├── TimeInterval+Format.swift    # 시간 포맷팅
│   │   │   └── Double+Distance.swift        # 거리 포맷팅
│   │   │
│   │   ├── UI/
│   │   │   ├── Theme.swift                  # 색상, 폰트 등 디자인 토큰
│   │   │   └── HapticManager.swift          # 햅틱 피드백 관리
│   │   │
│   │   └── Util/
│   │       ├── LocationUtils.swift          # 좌표 계산 유틸리티
│   │       └── DistanceCalculator.swift     # 거리 계산 (점-선분)
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets                  # 이미지, 색상 에셋
│   │   ├── Localizable.strings              # 다국어 (ko, en)
│   │   └── Info.plist
│   │
│   └── Preview Content/
│       └── Preview Assets.xcassets
│
├── NavigationTests/
│   ├── Service/
│   │   ├── OffRouteDetectorTests.swift
│   │   ├── GuidanceEngineTests.swift
│   │   └── StepTrackerTests.swift
│   └── ViewModel/
│       ├── SearchViewModelTests.swift
│       └── NavigationViewModelTests.swift
│
├── NavigationUITests/
│   └── NavigationFlowTests.swift
│
└── Documents/
    ├── PRD.md
    ├── TechSpec.md
    ├── Architecture.md
    └── Roadmap.md
```

---

## 3. Service Layer 상세 설계

### 3.1 LocationService

```
역할: CoreLocation 추상화, 위치 데이터 스트림 제공

Input:  시작/정지 명령
Output: CurrentValueSubject<CLLocation?, Never>
        CurrentValueSubject<CLHeading?, Never>
        CurrentValueSubject<LocationAuthStatus, Never>

주요 메서드:
- startUpdating()                → 위치 추적 시작
- stopUpdating()                 → 위치 추적 정지
- requestAuthorization()         → 위치 권한 요청
- configureForNavigation()       → 네비게이션 최적 설정
- configureForWalking()          → 도보 최적 설정

위치 정확도 필터링:
- horizontalAccuracy > 100m  → 무시
- horizontalAccuracy > 50m   → 경고 표시
- horizontalAccuracy <= 50m  → 사용
```

### 3.2 RouteService

```
역할: MKDirections 추상화, 경로 탐색/ETA 제공

주요 메서드:
- calculateRoutes(from:to:transportType:) → async throws [MKRoute]
- calculateETA(from:to:)                  → async throws MKDirections.ETAResponse
- cancelCurrentRequest()                  → 진행 중 요청 취소

에러 처리:
- network error     → 재시도 (3회, exponential backoff)
- no routes found   → 사용자 알림
- rate limited      → 대기 후 재시도
```

### 3.3 GuidanceEngine (핵심)

```
역할: 네비게이션 안내의 두뇌. 위치 업데이트를 받아 안내 이벤트를 발생시킴

의존성:
- LocationService (위치 스트림)
- RouteService (재경로 탐색)
- VoiceGuidanceService (음성 출력)
- OffRouteDetector (이탈 감지)
- StepTracker (현재 스텝 관리)

Output Publishers:
- currentStepPublisher      → 현재 안내 스텝
- nextManeuverPublisher     → 다음 회전 정보 (방향, 거리)
- distanceRemainingPublisher → 남은 거리
- etaPublisher              → 예상 도착 시간
- isOffRoutePublisher       → 경로 이탈 상태
- navigationStatePublisher  → 전체 상태 (navigating, rerouting, arrived)

처리 흐름:
LocationService.locationPublisher
    → OffRouteDetector.check()
        → 이탈 시: RerouteManager.reroute()
    → StepTracker.updateProgress()
        → 안내 필요 시: VoiceGuidanceService.speak()
    → UI 업데이트 (ViewModel로 전달)
```

### 3.4 OffRouteDetector

```
역할: 현재 위치가 경로에서 벗어났는지 감지

알고리즘:
1. 현재 세그먼트 인덱스 기준 ±5 세그먼트만 검사 (최적화)
2. 점-선분 최단거리 계산
3. 거리 > threshold → 이탈 카운터 증가
4. 연속 3회 이탈 → 이탈 확정

설정:
- offRouteThreshold: 50.0 (m)
- confirmationCount: 3
- checkInterval: 매 위치 업데이트
```

### 3.5 VoiceGuidanceService

```
역할: 음성 안내 텍스트 생성 및 TTS 출력

안내 유형:
- 회전 안내: "300미터 앞에서 우회전하세요"
- 직진 안내: "2킬로미터 직진하세요"
- 도착 안내: "목적지에 도착했습니다"
- 이탈 안내: "경로를 이탈했습니다. 새로운 경로를 탐색합니다"
- 재경로 안내: "새로운 경로로 안내합니다"

큐 관리:
- 새 안내가 들어오면 현재 발화 중단 후 새 안내
- 중요도: 이탈 > 회전 직전 > 회전 예고 > 직진
```

### 3.6 VehicleIconService

```
역할: 차량 아이콘 관리 (프리셋 / Lift Subject / 3D 모델)

의존성:
- Vision Framework (LiftSubjectProcessor)
- SceneKit (Vehicle3DRenderer)
- PhotosUI (PhotosPicker)
- SwiftData (VehicleIcon 모델)

주요 메서드:
- getActiveIcon()                         → 현재 사용 중인 아이콘
- createFromPhoto(image: UIImage)         → Lift Subject로 배경 제거 → 아이콘 생성
- load3DModel(named: String)              → USDZ/SCN 모델 로드
- getPresetIcons()                        → 기본 제공 프리셋 목록
- setActive(iconId: UUID)                 → 활성 아이콘 변경

LiftSubjectProcessor 처리 흐름:
UIImage → CIImage → VNGenerateForegroundInstanceMaskRequest
    → 마스크 생성 → CIBlendWithMask → 배경 제거 → PNG Data 저장

Vehicle3DRenderer:
- SCNView를 투명 배경으로 생성
- 차량 heading에 따라 SCNNode.eulerAngles.y 회전
- 지도 줌 레벨에 따라 모델 스케일 조절
- MapView 좌표 → 스크린 좌표 변환으로 위치 동기화
```

### 3.7 VirtualDriveEngine

```
역할: 경로를 따라 가상 주행 시뮬레이션

의존성:
- GuidanceEngine (안내 로직 공유)
- VoiceGuidanceService (음성 안내)
- MapInterpolator (부드러운 표현)

주요 메서드:
- start(route: MKRoute)                  → 가상 주행 시작
- pause()                                → 일시 정지
- resume()                               → 재개
- stop()                                 → 종료
- seek(progress: Double)                 → 특정 지점으로 이동 (0.0 ~ 1.0)
- setSpeed(multiplier: Double)           → 배속 설정 (1x ~ 8x)

Output Publishers:
- virtualLocationPublisher    → 현재 가상 위치
- progressPublisher           → 진행률 (0.0 ~ 1.0)
- elapsedTimePublisher        → 경과 시간
- isPlayingPublisher          → 재생 상태

내부 동작:
1. MKRoute.polyline → [CLLocationCoordinate2D] 추출
2. Timer (0.1초 간격) × speedMultiplier로 가상 시간 진행
3. 시간 → 해당 좌표 보간 → CLLocation 생성
4. → LocationService에 가상 위치 주입 (실제 GPS 우회)
5. GuidanceEngine은 가상/실제 구분 없이 동일 동작
```

### 3.8 GPXRecorder & GPXPlayer

```
GPXRecorder:
역할: 실시간 GPS 데이터를 GPX 파일로 녹화

주요 메서드:
- startRecording(name: String?)    → 녹화 시작
- stopRecording() -> GPXRecording  → 녹화 종료 + SwiftData 저장
- isRecording: Bool                → 녹화 상태

녹화 데이터 (매 GPS 업데이트):
- 위도, 경도, 고도
- 속도, 진행 방향 (course)
- 타임스탬프
- 수평 정확도

GPXPlayer:
역할: 저장된 GPX 파일을 로드하여 가상 위치로 재생

주요 메서드:
- load(recording: GPXRecording)    → GPX 파일 로드
- play()                           → 재생 시작
- pause()                          → 일시 정지
- setSpeed(multiplier: Double)     → 배속 (0.5x ~ 8x)
- seek(to: TimeInterval)           → 특정 시간으로 이동

Output:
- LocationService에 가상 위치 주입 (VirtualDriveEngine과 동일 메커니즘)
- 타임스탬프 기반 재생 (좌표 간 보간 적용)

GPXParser:
- GPX XML 파싱 → [CLLocation] 배열 변환
- GPX XML 생성 ← [CLLocation] 배열 변환
- Xcode GPX 포맷과 호환
```

### 3.9 MapInterpolator

```
역할: GPS 업데이트 사이 프레임 보간으로 부드러운 지도 표현

의존성:
- QuartzCore (CADisplayLink)
- MapKit (MKMapView, MKMapCamera)

동작:
1. CADisplayLink로 매 프레임 콜백 등록 (60fps)
2. 이전 GPS 위치 → 현재 GPS 위치 사이를 시간 비율로 보간
3. 보간된 위치로 차량 아이콘 + 카메라 업데이트

보간 대상:
- LocationInterpolator: 위도/경도 선형 보간 (Lerp)
- HeadingInterpolator: heading 최단 각도 보간
  → angleDiff = ((target - current + 540) % 360) - 180
  → interpolated = current + angleDiff * t
- CameraInterpolator: MKMapCamera 전체 보간
  → centerCoordinate, heading, altitude, pitch

메서드:
- start()                          → CADisplayLink 시작
- stop()                           → CADisplayLink 정지
- updateTarget(location:heading:)   → 새 GPS 데이터 수신 시 타겟 갱신
- getCurrentInterpolated()          → 현재 보간된 위치/방향

성능:
- 보간 계산: < 0.5ms per frame
- 메인 스레드에서 실행 (UI 업데이트와 동기화)
- 네비게이션 비활성 시 자동 정지
```

### 3.10 TurnPointPopupService

```
역할: 회전 지점/목적지 도착 접근 시 정북 2D 팝업 안내

의존성:
- GuidanceEngine (현재 스텝 + 다음 스텝 정보)
- LocationService (현재 위치 → 팝업 내 차량 위치 실시간 반영)
- StepTracker (회전 지점까지 남은 거리)

트리거 로직:
1. 다음 회전 지점까지 남은 거리 < 300m → 회전 지점 팝업 표시
2. 최종 목적지까지 남은 거리 < 300m → 목적지 도착 팝업 표시
3. 회전 지점 통과 → 팝업 닫기
4. 목적지 도착 판정 → 팝업 닫기 + 도착 안내

팝업 구성:
- 별도 MKMapView 인스턴스 (터치 비활성)
- 정북 고정 (heading=0), 2D 탑뷰 (pitch=0)
- 중심 좌표 = 목표 지점 좌표 (회전 지점 or 목적지, 고정, 차량을 따라가지 않음)
- 줌 레벨: 트리거 시 차량 위치(300m 전)와 회전 지점이 모두 화면에 들어오는 범위
  → 두 좌표 포함 MKCoordinateRegion + 20% 패딩으로 altitude 동적 계산
- 경로 polyline 강조 표시 (현재 스텝 + 다음 스텝 polyline 렌더링)
- 차량 annotation: raw GPS 좌표 그대로 표시 (경로 스냅 X)
  → 메인 지도는 경로 매칭, 팝업은 CLLocation.coordinate 직접 사용
  → 실제 위치와 경로 간 관계를 사용자가 직관적으로 파악
- 차량 annotation이 팝업 가장자리에서 출발 → 중심(회전 지점) 향해 리얼타임 이동
- LocationService 구독하여 매 GPS 업데이트마다 차량 annotation 좌표 갱신

팝업 타입:
- .turnPoint(coordinate: CLLocationCoordinate2D) → 회전 지점 팝업
- .destination(coordinate: CLLocationCoordinate2D) → 목적지 도착 팝업
- 동일한 팝업 뷰를 공유, 중심 좌표와 마커 스타일만 다름

Output Publishers:
- showPopupPublisher      → Bool (팝업 표시/숨김)
- popupTypePublisher      → PopupType (.turnPoint / .destination)
- popupConfigPublisher    → PopupConfig
  (centerCoordinate, routePolyline, calculatedAltitude, triggerVehicleCoordinate)
- vehiclePositionPublisher → 팝업 내 raw GPS 좌표 (경로 스냅 없이 LocationService 직접 연동)
```

---

## 4. 데이터 흐름

### 4.1 검색 → 결과 표시 → 안내 시작 플로우

```
[HomeView - 검색 바 탭]
    │  "여기서 검색" 탭
    ▼
[SearchView - 자동완성 모드]
    │  키보드 활성 + 즐겨찾기/최근 검색 표시
    │  입력 시 MKLocalSearchCompleter → 자동완성
    │  region = mapView.region (현재 보이는 영역)
    ▼
[SearchViewModel - 검색 실행]
    │  MKLocalSearch(region: visibleRegion)
    │  → [MKMapItem] 검색 결과
    ▼
[HomeView - 검색 결과 상태]  ★ 화면 전환 없이 같은 HomeView
    │
    ├── [지도] 결과 마커 일괄 표시 (MKAnnotation)
    │         최상단 항목 마커 강조 (선택 상태)
    │
    └── [SearchResultDrawer - Bottom Sheet]
          │  최소 / 중간 / 전체 3단계 높이
          │  내부 스크롤 가능한 결과 리스트
          │
          ├── 스크롤 → DrawerListFocusTracker
          │     │  최상단 visible item 감지
          │     │  → 지도 카메라 해당 마커로 이동
          │     │  → 해당 마커 선택(강조) 상태
          │     ▼
          │   [MapView 포커스 업데이트]
          │
          └── 마커 탭 (역방향)
                │  지도에서 마커 탭
                │  → 드로어 리스트 해당 항목으로 스크롤
                │  → 해당 항목 하이라이트
    ▼
[결과 항목 탭 → RoutePreviewView]
    │  목적지 선택
    ▼
[RoutePreviewViewModel]
    │  RouteService.calculateRoutes()
    │  → [MKRoute] 경로 후보들
    ▼
[NavigationView]
    │  "안내 시작" 탭
    ▼
[NavigationViewModel]
    │  GuidanceEngine.start(route:)
    │  LocationService.startUpdating()
    │  VoiceGuidanceService.enable()
    ▼
[GuidanceEngine - 실시간 루프]
    │  Location 수신 → 이탈 체크 → 스텝 추적 → 안내 트리거
    ▼
[NavigationView 업데이트]
    → MapInterpolator → 부드러운 카메라/아이콘 이동
    → 다음 회전 배너 업데이트
    → TurnPointPopupService → 회전 지점 팝업 안내
    → 하단 바 (거리/시간) 업데이트
    → 음성 안내 출력
```

### 4.2 CarPlay 데이터 흐름

```
[CarPlayService]
    │  CPTemplateApplicationSceneDelegate
    ▼
[CPMapTemplate] ←── GuidanceEngine 공유
    │                (iPhone과 동일한 엔진 사용)
    ▼
[CPNavigationSession]
    │  CPManeuver 업데이트 ← GuidanceEngine.nextManeuverPublisher
    │  CPTravelEstimates   ← GuidanceEngine.etaPublisher
    ▼
[CarPlay 화면 자동 업데이트]
```

> **핵심**: iPhone과 CarPlay는 동일한 `GuidanceEngine` 인스턴스를 공유.
> ViewModel만 다르고, 안내 로직은 하나.

---

## 5. 상태 관리

### 5.1 앱 전체 상태

```swift
enum AppState {
    case idle                    // 메인 화면, 안내 없음
    case searching               // 검색 중
    case routePreview            // 경로 미리보기
    case navigating              // 안내 중
    case rerouting               // 재경로 탐색 중
    case arrived                 // 목적지 도착
}
```

### 5.2 GuidanceEngine 상태

```swift
enum GuidanceState {
    case inactive                // 비활성
    case preparing               // 경로 준비 중
    case navigating(RouteProgress) // 안내 중 + 진행 정보
    case rerouting               // 재경로 탐색
    case arrived                 // 도착
    case error(GuidanceError)    // 에러
}
```

---

## 6. 의존성 주입

```
SwiftUI Environment + ObservableObject 기반

@main NavigationApp
    └── .environment(LocationService.shared)
    └── .environment(RouteService())
    └── .environment(SearchService())
    └── .environment(VehicleIconService())
    └── .environment(MapInterpolator())
    └── .environment(TurnPointPopupService())
    └── .modelContainer(for: [FavoritePlace.self, SearchHistory.self,
                               NavigationRecord.self, VehicleIcon.self,
                               GPXRecording.self])

각 ViewModel은 init에서 Service를 주입받음
테스트 시 Mock Service로 교체 가능

LocationService 위치 소스 전략:
- 실제 GPS (기본)
- VirtualDriveEngine → 가상 주행 시 가상 위치 주입
- GPXPlayer → GPX 재생 시 녹화된 위치 주입
- LocationService.setLocationSource(provider:) 로 전환
```

---

## 7. CarPlay 아키텍처

```
NavigationApp
├── iPhone Scene (UIWindowScene)
│   └── SwiftUI Views + ViewModels
│
└── CarPlay Scene (CPTemplateApplicationScene)
    └── CarPlayService
        ├── CPMapTemplate (지도)
        ├── CPSearchTemplate (검색)
        ├── CPListTemplate (즐겨찾기/최근)
        └── CPNavigationSession (안내)
            └── GuidanceEngine (공유 인스턴스)

동기화:
- iPhone에서 안내 시작 → CarPlay 자동 반영
- CarPlay에서 목적지 선택 → iPhone 안내 화면 전환
- 공유: GuidanceEngine, LocationService, RouteService
- 독립: UI 렌더링 (각자의 화면에 맞게)
```

---

## 8. 스레드 모델

```
Main Thread:
- UI 업데이트
- MapView 렌더링
- SwiftUI View body
- CADisplayLink 보간 콜백 (MapInterpolator)
- SceneKit 3D 차량 렌더링

Background (async/await):
- MKDirections 경로 탐색
- MKLocalSearch 검색
- CLGeocoder 주소 변환
- SwiftData 읽기/쓰기
- Vision Lift Subject 처리 (이미지 배경 제거)
- GPX 파일 파싱/생성

Location Thread (시스템 관리):
- CLLocationManager delegate callbacks
- → Main thread로 publish (via Combine)
- VirtualDriveEngine / GPXPlayer도 동일 경로로 publish

Audio Thread (시스템 관리):
- AVSpeechSynthesizer 음성 출력

Display Link Thread (Main Thread RunLoop):
- CADisplayLink 60fps 콜백
- 위치 보간 계산 → 차량 아이콘 위치 업데이트
- 카메라 보간 계산 → MKMapView.setCamera()
```
