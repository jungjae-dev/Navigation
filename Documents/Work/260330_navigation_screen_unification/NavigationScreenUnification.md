# 주행 화면 통합 — 개발 계획서

## 1. 개요

### 배경
현재 주행 관련 화면이 3개로 분리되어 있다:
- **NavigationViewController** — 실제 턴바이턴 네비게이션 (전용 클래스)
- **가상 주행** — `AppCoordinator.startVirtualDrive()`에서 인라인 `UIViewController()` 생성
- **GPX 재생** — `AppCoordinator.startGPXPlayback()`에서 인라인 `UIViewController()` 생성

가상 주행과 GPX 재생은 전용 VC 없이 코디네이터에서 ~120줄씩 인라인으로 컨테이너를 구성하며, UI 패턴(맵 + 오버레이 컨트롤)이 거의 동일하다. 실제 주행 화면도 동일한 기반(맵 + 오버레이) 위에 턴바이턴 안내 UI가 추가된 구조다.

### 목표
- 3개 화면을 **NavigationViewController 1개로 통합**
- `NavigationMode` enum으로 모드 분기
- 코디네이터의 인라인 컨테이너 구성 코드 ~240줄 제거
- `VirtualDriveControlView`와 `GPXPlaybackControlView`를 통합

### 관련 파일 (현재)

```
Feature/Navigation/
  NavigationViewController.swift      ← 통합 대상 (확장)
  NavigationViewModel.swift           ← GuidanceEngine optional화
  NavigationBottomBar.swift           ← 변경 없음
  ManeuverBannerView.swift            ← 변경 없음

Feature/VirtualDrive/
  VirtualDriveControlView.swift       ← PlaybackControlView로 통합 후 삭제

Feature/DevTools/
  GPXPlaybackControlView.swift        ← PlaybackControlView로 통합 후 삭제

Service/VirtualDrive/
  VirtualDriveEngine.swift            ← PlaybackControllable 프로토콜 적용

Service/DevTools/
  GPXSimulator.swift                  ← PlaybackControllable 프로토콜 적용

Coordinator/
  AppCoordinator.swift                ← startVirtualDrive/startGPXPlayback 대폭 축소
```

---

## 2. 현재 구현 비교

### 화면 구조 비교

```
실제 주행 (NavigationViewController)
┌─────────────────────────┐
│  ManeuverBannerView     │  ← 턴 안내 (아이콘 + 거리 + 지시)
│                         │
│      MapViewController  │  ← 전체 화면 맵
│                         │
│  [리센터]               │  ← 우측 (조건부 표시)
│  [3D 차량]              │  ← 하단 중앙 (설정에 따라)
│  [턴포인트 팝업]         │  ← 좌측 하단 (300m 이내)
│  NavigationBottomBar    │  ← ETA, 잔여거리/시간, 종료 버튼
└─────────────────────────┘

가상 주행 / GPX 재생
┌─────────────────────────┐
│  [X 닫기]               │  ← 좌측 상단
│                         │
│      MapViewController  │  ← 전체 화면 맵
│                         │
│  PlaybackControlView    │  ← 하단 (재생/정지/속도 + 프로그래스 바)
└─────────────────────────┘
```

### 인터페이스 비교

| 항목 | NavigationViewModel | VirtualDriveEngine | GPXSimulator |
|------|--------------------|--------------------|--------------|
| **위치 소스** | `LocationService.locationPublisher` | `simulatedLocationPublisher` (CurrentValueSubject) | `simulatedLocationPublisher` (PassthroughSubject) |
| **헤딩** | `LocationService.headingPublisher` | `simulatedHeadingPublisher` | 없음 (CLLocation.course) |
| **MapInterpolator** | 사용 | 사용 | **미사용** |
| **GuidanceEngine** | 사용 | 미사용 | 미사용 |
| **재생 상태** | N/A | `PlayState` enum (idle/playing/paused/finished) | `Bool` (isPlaying) |
| **프로그래스** | N/A | `progressPublisher` (0.0~1.0) | `progressPublisher` (0.0~1.0) |
| **속도 배율** | N/A | `speedMultiplierPublisher` + `cycleSpeed()` | `speedMultiplier` property + didSet |
| **컨트롤 뷰** | ManeuverBanner + BottomBar | VirtualDriveControlView | GPXPlaybackControlView |
| **종료 콜백** | `onDismiss` | `onStop` (코디네이터에서 처리) | `onStop` (코디네이터에서 처리) |

---

## 3. 설계

### 3.1 NavigationMode enum

```swift
enum NavigationMode {
    case realNavigation(session: NavigationSession)
    case virtualDrive(engine: VirtualDriveEngine)
    case gpxPlayback(simulator: GPXSimulator)
}
```

### 3.2 PlaybackControllable 프로토콜

`VirtualDriveEngine`과 `GPXSimulator`의 재생 제어를 통일한다.

```swift
protocol PlaybackControllable: AnyObject {
    var isPlayingPublisher: CurrentValueSubject<Bool, Never> { get }
    var progressPublisher: CurrentValueSubject<Double, Never> { get }
    var speedMultiplierPublisher: CurrentValueSubject<Double, Never> { get }

    func play()
    func pause()
    func stop()
    func cycleSpeed()
}
```

**VirtualDriveEngine 적용:**
- `isPlayingPublisher` 추가 — `playStatePublisher`에서 파생 (`playState == .playing`)
- `cycleSpeed()` — 이미 존재

**GPXSimulator 적용:**
- `cycleSpeed()` 추가 — 현재 코디네이터에 인라인 구현 (speeds 배열 순환)
- `isPlayingPublisher` — 이미 존재

### 3.3 PlaybackControlView (통합)

`VirtualDriveControlView`와 `GPXPlaybackControlView`를 하나로 통합한다.

```swift
final class PlaybackControlView: UIView {
    var onPlayPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onSpeedCycle: (() -> Void)?

    func bind(to source: PlaybackControllable)
}
```

- UI: play/pause 버튼, stop 버튼, speed 버튼, progress bar, status 라벨
- 테마: VirtualDriveControlView 스타일 (다크 반투명) 통일

### 3.4 NavigationViewController 확장

```swift
final class NavigationViewController: UIViewController {

    // --- 기존 (실제 주행용) ---
    private let maneuverBanner: ManeuverBannerView       // realNavigation에서만 표시
    private let bottomBar: NavigationBottomBar            // realNavigation에서만 표시
    private let recenterButton: UIButton                  // realNavigation에서만 표시
    private var turnPointPopupView: TurnPointPopupView?   // realNavigation에서만
    private var vehicle3DOverlay: Vehicle3DOverlayView?   // realNavigation에서만

    // --- 추가 (시뮬레이션용) ---
    private var playbackControlView: PlaybackControlView? // virtualDrive/gpxPlayback에서만 표시
    private var closeButton: UIButton?                    // virtualDrive/gpxPlayback에서만 표시

    // --- 모드 ---
    private let mode: NavigationMode

    // --- Init 변경 ---
    init(
        mode: NavigationMode,
        mapViewController: MapViewController,
        viewModel: NavigationViewModel?,           // nil for simulation modes
        turnPointPopupService: TurnPointPopupService?  // nil for simulation modes
    )
}
```

**모드별 UI 분기 (viewDidLoad):**

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupMapChild()

    switch mode {
    case .realNavigation:
        setupNavigationOverlays()   // maneuverBanner, bottomBar, recenterButton, 3DOverlay
        bindViewModel()
        bindPopup()

    case .virtualDrive(let engine):
        setupPlaybackOverlays()     // closeButton, playbackControlView
        playbackControlView?.bind(to: engine)

    case .gpxPlayback(let simulator):
        setupPlaybackOverlays()     // closeButton, playbackControlView
        playbackControlView?.bind(to: simulator)
    }
}
```

### 3.5 위치 → 맵 파이프라인 통일

현재 GPX 재생만 `LocationService.startLocationOverride()` 방식을 사용한다.
3개 모드 모두 **MapInterpolator**를 통해 카메라를 제어하도록 통일한다.

```
모드별 위치 소스                        공통 파이프라인
─────────────────────                ──────────────────
realNav:    LocationService.pub ──┐
virtualDrv: VDEngine.simLocPub  ──┼──▶ MapInterpolator ──▶ MapVC.applyCamera()
gpxPlay:    GPXSim.simLocPub   ──┘
```

**GPX 재생 변경점:**
- `LocationService.startLocationOverride()` 호출 제거
- GPXSimulator의 `simulatedLocationPublisher`를 직접 MapInterpolator에 연결
- 헤딩: `CLLocation.course` 값 사용

### 3.6 AppCoordinator 변경

**기존 (3개 메서드, ~350줄):**
```swift
func startNavigation()      // ~80줄
func startVirtualDrive()    // ~120줄 (인라인 컨테이너 구성)
func startGPXPlayback()     // ~100줄 (인라인 컨테이너 구성)
```

**변경 후 (1개 공통 + 3개 모드별, ~150줄):**
```swift
private func presentNavigationScreen(mode: NavigationMode, route: MKRoute? = nil) {
    let navMapVC = createNavigationMapVC()
    self.navigationMapViewController = navMapVC

    // 모드별 맵 설정
    switch mode {
    case .realNavigation:
        navMapVC.configureForNavigation()
        navMapVC.showSingleRoute(route!)

    case .virtualDrive:
        navMapVC.configureForNavigation()
        navMapVC.showSingleRoute(route!)

    case .gpxPlayback(let simulator):
        // GPX 트랙 오버레이
        // ...
    }

    // 공통: MapCamera + MapInterpolator
    let camera = MapCamera()
    let interpolator = MapInterpolator(mapCamera: camera)
    self.mapCamera = camera
    self.mapInterpolator = interpolator
    interpolator.start(mapViewController: navMapVC)

    // 모드별 위치 피드 연결
    // ...

    // NavigationVC 생성 + push
    let navVC = NavigationViewController(
        mode: mode,
        mapViewController: navMapVC,
        viewModel: viewModel,              // nil for simulation
        turnPointPopupService: popupService // nil for simulation
    )
    navigationController.pushViewController(navVC, animated: true)
}
```

**삭제 대상:**
- `startVirtualDrive()` 인라인 컨테이너 구성 (~120줄)
- `startGPXPlayback()` 인라인 컨테이너 구성 (~100줄)

**`stopVirtualDrive()`와 `stopGPXPlayback()` 통합:**
```swift
private func stopSimulation() {
    virtualDriveEngine?.stop()
    virtualDriveEngine = nil
    gpxSimulator?.stop()
    gpxSimulator = nil
    mapInterpolator?.stop()
    mapInterpolator = nil
    mapCamera = nil
    navigationMapViewController = nil
    navigationController.popToViewController(homeViewController, animated: true)
    presentHomeDrawer()
}
```

---

## 4. 변경 파일 목록

### 새 파일
| 파일 | 설명 |
|------|------|
| `Service/Protocol/PlaybackControllable.swift` | 재생 제어 프로토콜 |
| `Feature/Navigation/PlaybackControlView.swift` | 통합 재생 컨트롤 뷰 |
| `Feature/Navigation/NavigationMode.swift` | NavigationMode enum |

### 수정 파일
| 파일 | 변경 내용 |
|------|----------|
| `Feature/Navigation/NavigationViewController.swift` | `mode` 기반 분기, playback UI 추가, init 변경 |
| `Feature/Navigation/NavigationViewModel.swift` | GuidanceEngine optional 처리 또는 모드별 init |
| `Service/VirtualDrive/VirtualDriveEngine.swift` | `PlaybackControllable` 채택, `isPlayingPublisher` 추가 |
| `Service/DevTools/GPXSimulator.swift` | `PlaybackControllable` 채택, `cycleSpeed()` 추가 |
| `Coordinator/AppCoordinator.swift` | 3개 start 메서드 → `presentNavigationScreen(mode:)` 통합 |

### 삭제 파일
| 파일 | 사유 |
|------|------|
| `Feature/VirtualDrive/VirtualDriveControlView.swift` | PlaybackControlView로 통합 |
| `Feature/DevTools/GPXPlaybackControlView.swift` | PlaybackControlView로 통합 |

---

## 5. 구현 순서

### Phase 1: 프로토콜 + 컨트롤 뷰 통합
1. `PlaybackControllable` 프로토콜 정의
2. `VirtualDriveEngine`에 프로토콜 적용
3. `GPXSimulator`에 프로토콜 적용 (`cycleSpeed()` 추가)
4. `PlaybackControlView` 작성 (두 컨트롤 뷰 통합)
5. 빌드 확인

### Phase 2: NavigationViewController 확장
1. `NavigationMode` enum 정의
2. `NavigationViewController` init 변경 (mode 파라미터 추가)
3. `viewDidLoad`에서 모드별 UI 분기
4. 시뮬레이션 모드용 closeButton + playbackControlView 레이아웃
5. 빌드 확인

### Phase 3: 위치 파이프라인 통일
1. GPXSimulator의 LocationService override 방식 제거
2. 모든 모드에서 MapInterpolator 경유하도록 통일
3. NavigationViewController에서 모드별 위치 구독 설정
4. 빌드 확인

### Phase 4: AppCoordinator 통합
1. `presentNavigationScreen(mode:)` 공통 메서드 작성
2. `startNavigation()` → `presentNavigationScreen(.realNavigation)` 호출로 변경
3. `startVirtualDrive()` → `presentNavigationScreen(.virtualDrive)` 호출로 변경
4. `startGPXPlayback()` → `presentNavigationScreen(.gpxPlayback)` 호출로 변경
5. `stopVirtualDrive()` + `stopGPXPlayback()` → `stopSimulation()` 통합
6. 기존 인라인 컨테이너 코드 삭제
7. 빌드 확인

### Phase 5: 정리
1. `VirtualDriveControlView.swift` 삭제
2. `GPXPlaybackControlView.swift` 삭제
3. 빌드 + 시뮬레이터 테스트

---

## 6. 검증

### 테스트 시나리오
1. **실제 주행**: 경로 미리보기 → 안내 시작 → 턴배너/하단바/리센터 표시 → 안내 종료 → 홈 복귀
2. **가상 주행**: 경로 미리보기 → 가상 주행 → 재생컨트롤 표시 → 재생/정지/속도 변경 → 닫기 → 홈 복귀
3. **GPX 재생**: 설정 → GPX 파일 선택 → 재생컨트롤 표시 → 재생/정지/속도 변경 → 닫기 → 홈 복귀
4. **공통**: 각 모드 종료 후 홈 지도 정상 표시 확인 (검정 화면 없음, 위치 유지)
5. **CarPlay**: 실제 주행만 CarPlay 연동 확인, 시뮬레이션 모드는 CarPlay 미연동 확인

### 회귀 테스트
- 드로어 시트 동작 (홈/검색/POI/경로 미리보기)
- 맵 인셋 및 컨트롤 위치
- 즐겨찾기/최근검색에서 경로 미리보기 진입
