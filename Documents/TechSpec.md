# Navigation App - Technical Specification

## 1. 기술 스택

| 카테고리 | 기술 | 버전/비고 |
|---------|------|----------|
| Language | Swift | 5.9+ |
| Minimum Target | iOS 17.0 | |
| UI Framework | SwiftUI + UIKit | SwiftUI 메인, MapKit은 UIViewRepresentable |
| Map | MapKit | MKMapView |
| Routing | MKDirections | Apple 경로 탐색 API |
| Location | CoreLocation | CLLocationManager |
| Voice | AVFoundation | AVSpeechSynthesizer |
| CarPlay | CarPlay Framework | CPNavigationSession |
| Local Storage | SwiftData | iOS 17+ 네이티브 |
| Reactive | Combine | 데이터 흐름 |
| Haptics | CoreHaptics | 회전 지점 피드백 |
| Vision | Vision Framework | Lift Subject (배경 제거) |
| 3D Rendering | SceneKit | 3D 차량 모델 렌더링 |
| Photo Picker | PhotosUI | PhotosPicker (차량 사진 선택) |
| Frame Sync | QuartzCore | CADisplayLink (프레임 보간) |
| Build | Xcode 15+ | Swift Package Manager |

---

## 2. Apple API 상세 활용

### 2.1 경로 탐색 - MKDirections

```
사용 API:
- MKDirections.Request     → 경로 요청 구성
- MKDirections.calculate() → 경로 계산
- MKDirections.calculateETA() → 간편 ETA 요청
- MKRoute                  → 경로 결과 (polyline, steps, ETA, distance)
- MKRouteStep              → 개별 안내 단계 (instructions, distance, polyline)

지원 TransportType:
- .automobile  → 자동차 경로
- .walking     → 도보 경로

제한사항:
- Apple 서버 의존 (오프라인 불가)
- 요청 제한: 초당 1회 권장, 과도한 요청 시 throttle
- 한국 도로 데이터는 Apple Maps 기반 (네이버/카카오 대비 제한적일 수 있음)
```

### 2.2 장소 검색 - MKLocalSearch

```
사용 API:
- MKLocalSearchCompleter        → 검색어 자동완성
- MKLocalSearchCompletion       → 자동완성 결과
- MKLocalSearch.Request         → 검색 요청
- MKLocalSearch                 → 검색 실행
- MKMapItem                     → 검색 결과 (장소 정보)
- MKCoordinateRegion             → 지도 visible region 기반 검색

기능:
- naturalLanguageQuery  → 자연어 검색 ("근처 주유소")
- region 기반 필터링    → 현재 지도 visible region 기준 ("여기서 검색")
- resultTypes           → .pointOfInterest, .address, .query
- pointOfInterestFilter → 카테고리 필터링

"여기서 검색" 동작:
- MKLocalSearch.Request.region = mapView.region (현재 보이는 영역)
- 지도 이동/줌 시 region 자동 갱신
- 자동완성: MKLocalSearchCompleter.region도 동일 영역 적용
- 검색 결과: [MKMapItem] → 지도 위 MKAnnotation으로 마커 표시
```

### 2.3 주소 변환 - CLGeocoder

```
사용 API:
- CLGeocoder.geocodeAddressString()     → 주소 → 좌표 (Forward)
- CLGeocoder.reverseGeocodeLocation()   → 좌표 → 주소 (Reverse)
- CLPlacemark                           → 장소 상세 정보

용도:
- 현재 위치의 도로명/주소 표시
- 목적지 주소 → 좌표 변환
- 검색 결과 주소 표시
```

### 2.4 위치 추적 - CoreLocation

```
사용 API:
- CLLocationManager                 → 위치 관리자
- CLLocation                        → 위치 데이터 (좌표, 속도, 방향, 고도)
- CLLocationManagerDelegate         → 위치 업데이트 수신
- CLCircularRegion                  → 지오펜싱 (회전 지점 감지)

설정:
- desiredAccuracy: kCLLocationAccuracyBestForNavigation
- distanceFilter: 10.0 (10m마다 업데이트)
- activityType: .automotiveNavigation / .fitness (도보)
- allowsBackgroundLocationUpdates: true
- showsBackgroundLocationIndicator: true
- pausesLocationUpdatesAutomatically: false

권한:
- When In Use → 기본 (포그라운드 네비게이션)
- Always → 선택 (백그라운드 안내 지속)
```

### 2.5 음성 안내 - AVSpeechSynthesizer

```
사용 API:
- AVSpeechSynthesizer              → TTS 엔진
- AVSpeechUtterance                → 음성 발화 단위
- AVSpeechSynthesisVoice           → 음성 선택 (ko-KR)
- AVAudioSession                   → 오디오 세션 관리

설정:
- voice: ko-KR (한국어)
- rate: 0.48~0.52 (적절한 속도)
- volume: 1.0
- pitchMultiplier: 1.0

오디오 세션:
- category: .playback
- mode: .voicePrompt
- options: .duckOthers (다른 앱 오디오 볼륨 낮춤)
- options: .interruptSpokenAudioAndMixWithOthers
```

### 2.6 CarPlay - CarPlay Framework

```
사용 API:
- CPMapTemplate                    → 지도 화면 템플릿
- CPSearchTemplate                 → 검색 화면
- CPListTemplate                   → 목록 화면 (즐겨찾기, 최근)
- CPNavigationSession              → 네비게이션 세션
- CPTrip                           → 경로 정보
- CPRouteChoice                    → 경로 선택지
- CPManeuver                       → 회전 안내 정보
- CPTravelEstimates                → 남은 시간/거리
- CPNavigationAlert                → 네비 알림

필수 설정:
- Info.plist: UIApplicationSceneManifest → CarPlay scene 등록
- Entitlements: com.apple.developer.carplay-navigation
- CPTemplateApplicationSceneDelegate 구현

제한사항:
- CarPlay 개발자 권한 필요 (Apple Developer에서 신청)
- 시뮬레이터로 테스트 가능 (Xcode CarPlay Simulator)
- 템플릿 기반 UI만 가능 (자유 커스텀 불가)
```

### 2.7 햅틱 피드백 - CoreHaptics

```
사용 API:
- UIImpactFeedbackGenerator         → 간단한 충격 피드백
- UINotificationFeedbackGenerator    → 알림 피드백 (성공/경고/에러)
- CHHapticEngine                     → 커스텀 햅틱 (고급)

용도:
- 회전 지점 접근 시: .warning 피드백
- 경로 이탈 시: .error 피드백
- 목적지 도착 시: .success 피드백
- 경로 선택 시: .light impact
```

### 2.8 배경 제거 (Lift Subject) - Vision Framework

```
사용 API:
- VNGenerateForegroundInstanceMaskRequest  → 전경 객체 마스크 생성
- VNImageRequestHandler                   → 이미지 분석 실행
- IndexSet (allInstances)                  → 감지된 객체 선택
- generateScaledMaskForImage()             → 스케일된 마스크 추출
- CIImage / CIFilter                      → 마스크 적용하여 배경 제거

처리 흐름:
1. 사용자가 차량 사진 선택 (PhotosPicker)
2. VNGenerateForegroundInstanceMaskRequest로 전경 마스크 생성
3. CIFilter.applyingFilter("CIBlendWithMask")로 배경 제거
4. 결과 이미지를 차량 아이콘으로 저장

제한사항:
- iOS 17+ 필수
- 시뮬레이터 미지원 (실기기에서만 동작)
- 처리 시간: 1~3초 (이미지 크기에 따라)
- 차량이 명확히 구분되는 사진일수록 품질 좋음
```

### 2.9 3D 모델 렌더링 - SceneKit

```
사용 API:
- SCNView                                  → 3D 렌더링 뷰
- SCNScene                                 → 3D 씬 관리
- SCNNode                                  → 3D 오브젝트 노드
- SCNRenderer                              → 오프스크린 렌더링
- USDZ / SCN                               → 3D 모델 포맷

지도 위 3D 차량 렌더링 방식:
- MapKit은 3D annotation을 공식 지원하지 않음
- 투명 배경의 SCNView를 MKMapView 위에 오버레이
- 지도 카메라와 SCNView 카메라를 수동 동기화
- 차량 heading에 따라 SCNNode 회전

지원 포맷:
- .usdz (권장 - RealityKit/SceneKit 네이티브)
- .scn (SceneKit 네이티브)
- .obj / .dae (변환 가능)

성능 고려:
- SCNView.preferredFramesPerSecond = 60
- SCNView.antialiasingMode = .multisampling4X
- 네비게이션 중 렌더링 부하 최소화 (단일 차량 모델만)
```

---

## 3. 직접 구현 필요 기능

### 3.1 경로 이탈 감지 (Off-Route Detection)

```
알고리즘:
1. 현재 위치 → 경로 폴리라인 위 최근접점까지 거리 계산
2. 거리 > 50m → 이탈 판정
3. 연속 3회 이탈 확인 → 재경로 탐색 트리거
4. 재경로 탐색 중 debounce (10초 간격)

최적화:
- 전체 폴리라인이 아닌, 현재 세그먼트 ± 5개 구간만 검사
- 점 대 선분(point-to-segment) 거리 계산으로 정확도 향상
```

### 3.2 안내 타이밍 엔진 (Guidance Timing)

```
안내 트리거 로직:
1. MKRoute.steps 에서 모든 회전 지점 추출
2. 현재 위치 → 다음 회전 지점까지 거리 실시간 계산
3. 거리 기반 안내:
   - 자동차: 500m → 300m → 100m → 직전
   - 도보:   200m → 100m → 50m  → 직전
4. 이미 안내한 지점은 스킵 (중복 방지)
5. 회전 지점 통과 판정 → 다음 스텝으로 이동

속도 기반 보정:
- 고속도로 (80km/h+): 1km → 500m → 200m
- 시내 (40km/h 이하): 300m → 100m → 직전
- 도보 (5km/h 이하): 100m → 50m → 직전
```

### 3.3 카메라 추적 (Map Camera Control)

```
동작:
- 네비게이션 중: 현재 위치 + 진행 방향으로 카메라 자동 회전
- 사용자 제스처 감지 시: 자동 추적 해제 + "재추적" 버튼 표시
- 재추적 버튼 탭: 카메라 다시 현재 위치로

카메라 파라미터:
- heading: 진행 방향 (course)
- pitch: 45° (3D 시점) / 0° (2D 시점)
- altitude: 속도에 따라 동적 조절
  - 정지/저속: 500m
  - 시내: 1000m
  - 고속: 2000m
- centerCoordinateDistance: 현재 위치에서 진행 방향으로 약간 앞
```

### 3.4 ETA 실시간 업데이트

```
업데이트 주기:
- 1분마다 MKDirections.calculateETA() 호출
- 또는 경로 이탈 후 재탐색 시 갱신

표시 형식:
- 남은 시간: "15분" / "1시간 23분"
- 남은 거리: "8.2km" / "350m"
- 도착 예정: "14:35"
```

### 3.5 부드러운 지도 표현 (Smooth Map Rendering)

```
문제:
- GPS 업데이트 주기: ~1Hz (초당 1회)
- 화면 렌더링 주기: 60fps (초당 60프레임)
- → 보간 없이는 차량이 1초마다 "순간이동"하는 것처럼 보임

해결: Frame-based Interpolation

1. 차량 아이콘 위치 보간
   - 이전 GPS 좌표 → 현재 GPS 좌표 사이를 60프레임에 걸쳐 선형 보간
   - Lerp(A, B, t) where t = elapsed / interval
   - 위도/경도 각각 독립적으로 보간

2. 차량 아이콘 방향(heading) 보간
   - 이전 heading → 현재 heading 사이를 보간
   - 최단 각도 경로로 회전 (예: 350° → 10° = +20° 회전, -340° 아님)
   - Slerp 또는 shortest-arc 보간

3. 지도 카메라 보간
   - centerCoordinate: 위치 보간과 동기화
   - heading: 차량 heading과 동기화 (부드러운 회전)
   - altitude: 속도 변화에 따른 점진적 줌 레벨 변경
   - pitch: 일정 유지 (45° 고정) 또는 속도 기반 조절

4. 구현 방식
   - CADisplayLink 기반 프레임 콜백 (60fps)
   - 매 프레임마다 보간된 위치/방향 계산
   - MKMapView.setCamera() 호출 (animated: false, 직접 제어)

5. 엣지 케이스
   - GPS 신호 끊김: 마지막 속도/방향으로 예측 이동 (dead reckoning)
   - 급격한 방향 전환: 보간 시간 단축 (빠른 반응)
   - 터널 진입/이탈: 예측 → 실제 위치 부드러운 보정

성능:
- CADisplayLink 콜백 비용: < 1ms per frame
- 보간 계산: 단순 선형, CPU 부하 무시 가능
```

### 3.6 가상 주행 엔진 (Virtual Drive Engine)

```
동작 원리:
1. MKRoute에서 전체 경로 polyline 좌표 추출
2. 설정 속도(기본 60km/h)로 좌표 간 이동 시뮬레이션
3. 가상 CLLocation 생성 → GuidanceEngine에 주입
4. 실제 GPS가 아닌 가상 위치로 안내 동작

핵심 로직:
- 경로 polyline 좌표 배열을 시간 기반으로 순회
- 각 세그먼트 길이 / 속도 = 해당 구간 소요 시간
- 현재 시간 → 해당 좌표 위치 보간
- 속도 배율: 1x / 2x / 4x / 8x

가상 위치 생성:
- coordinate: 보간된 좌표
- speed: 구간별 시뮬레이션 속도
- course: 다음 좌표 방향
- timestamp: 가상 타임스탬프
- horizontalAccuracy: 5.0 (시뮬레이션이므로 정확)

컨트롤:
- play / pause / seek(progress: Double)
- speedMultiplier: 1.0 ~ 8.0
- Timer 기반 틱 (0.1초 간격 × 배속)
```

### 3.7 검색 결과 드로어 & 마커-리스트 연동

```
Bottom Sheet 드로어:
- UISheetPresentationController 또는 커스텀 SwiftUI 구현
- 3단계 detent: .small (~120pt), .medium (~50%), .large (~90%)
- 드래그 제스처로 단계 전환
- 드로어 내부 ScrollView는 독립 스크롤

마커-리스트 연동 로직:
1. 검색 결과 수신 → [MKMapItem] 배열
2. 지도에 MKAnnotation 마커 일괄 추가
3. 드로어 리스트에 동일 배열 표시
4. 연동 동작:
   - 리스트 스크롤 → 최상단 visible item 감지
     → ScrollViewReader + GeometryReader로 visible item 계산
     → 해당 MKAnnotation 선택 (mapView.selectAnnotation)
     → 지도 카메라를 해당 좌표로 이동
   - 지도 마커 탭 → 해당 item으로 리스트 스크롤
     → ScrollViewReader.scrollTo(item.id)
     → 해당 item 하이라이트

최상단 항목 감지 알고리즘:
- 드로어 내부 ScrollView의 각 item에 GeometryReader 부착
- item의 minY가 드로어 상단 기준 threshold(0~50pt) 내에 있는 첫 번째 item
- debounce 0.15초 적용 (빠른 스크롤 중 과도한 지도 이동 방지)

마커 포커싱:
- 선택된 마커: 확대 + 강조색 (파란색)
- 비선택 마커: 기본 크기 + 회색
- 포커싱 시 지도 카메라: animated 이동 (0.3초)
- 전체 마커가 보이도록 줌 레벨은 유지하되, 포커스 마커 중심
```

### 3.8 GPS 경로 녹화/재생 (GPX Record & Playback)

```
녹화 (Record):
- 네비게이션 중 또는 자유 주행 중 GPS 데이터 기록
- 저장 포맷: GPX (GPS Exchange Format) XML
- 기록 데이터:
  <trkpt lat="37.5665" lon="126.9780">
    <ele>38.0</ele>          <!-- 고도 -->
    <time>2025-01-01T12:00:00Z</time>
    <speed>16.7</speed>      <!-- m/s (확장 필드) -->
    <course>45.0</course>    <!-- 진행 방향 (확장 필드) -->
  </trkpt>
- 저장 간격: 1초 (GPS 업데이트마다)
- 파일 관리: 날짜_시간_출발지_목적지.gpx

재생 (Playback):
- GPX 파일 로드 → CLLocation 배열로 파싱
- 타임스탬프 기반 실시간 재생
- LocationService에 가상 위치 주입 (실제 GPS 대체)
- 재생 속도 조절: 0.5x ~ 8x
- 재생 중 GuidanceEngine은 실제 주행과 동일하게 동작

용도:
- 개발 중 실차 테스트 없이 경로 디버깅
- 특정 구간 반복 테스트 (이탈, 재경로 등)
- Xcode GPX 파일과 호환 (Xcode 시뮬레이터에서도 사용 가능)
```

### 3.8 팝업 안내 (회전 지점 + 목적지 도착)

```
트리거 조건:
- 회전 지점: 다음 MKRouteStep의 회전 지점까지 거리 < 300m
- 목적지 도착: 최종 목적지까지 남은 거리 < 300m

동작:
1. 목표 지점 300m 전: 팝업 뷰 페이드인
2. 팝업 내용:
   - 별도 MKMapView 인스턴스 (메인 지도와 독립)
   - 정북 고정 2D 탑뷰 (heading = 0, pitch = 0)
   - 높은 줌 레벨로 목표 지점 주변 상세 표시
   - 올바른 경로 polyline을 강조색(파란색)으로 렌더링
   - 현재 차량 위치를 실시간 반영 (LocationService 구독)
3. 회전 지점 통과 / 목적지 도착 판정 → 팝업 페이드아웃

팝업 MKMapView 설정:
- camera.heading = 0 (정북 고정, 회전 안함)
- camera.pitch = 0 (완전 2D 탑뷰)
- camera.centerCoordinate = 목표 지점 좌표 (회전 지점 or 목적지, 고정, 차량 따라가지 않음)
- camera.altitude = 차량 트리거 위치(300m 전)와 회전 지점이 모두 보이는 값으로 계산
  → MKMapView.cameraBoundary 또는 MKCoordinateRegion으로 두 지점 포함 영역 산출
  → altitude ≈ 300~700 (차량-회전 지점 거리 + 여유 마진에 따라 동적 결정)
- isUserInteractionEnabled = false (터치 비활성)
- 경로 polyline overlay 표시 (주행해야 할 경로를 파란색 강조)
  → 현재 스텝 + 다음 스텝의 polyline을 팝업 지도에 렌더링
  → 사용자가 어디로 가야 하는지 시각적으로 명확히 인지
- 차량 위치 annotation: **raw GPS 좌표 그대로 표시 (경로 스냅 X)**
  → 메인 지도에서는 차량을 경로에 매칭(snap)하지만, 팝업에서는 하지 않음
  → CLLocation.coordinate를 그대로 annotation 좌표로 사용
  → 실제 차량이 도로의 어디에 있는지 리얼하게 파악 가능
  → 팝업 표시 시 차량은 가장자리에 위치
  → GPS 업데이트마다 차량 annotation 좌표 갱신
  → 차량이 중심(회전 지점)을 향해 이동하는 모습이 리얼하게 보임

줌 레벨 계산 로직:
- 트리거 시점의 차량 좌표 + 회전 지점 좌표 → 두 점을 포함하는 MKCoordinateRegion 계산
- region에 상하좌우 20% 패딩 추가 (회전 후 경로도 일부 보이도록)
- MKMapCamera(lookingAtCenter: 회전지점, fromDistance: 계산된altitude, pitch: 0, heading: 0)

API 데이터 활용:
- MKRouteStep.instructions → 회전 방향 텍스트 ("우회전", "좌회전" 등)
- MKRouteStep.polyline → 올바른 경로 좌표 (강조 표시용)
- MKRouteStep.distance → 트리거 거리 계산
- ※ 분기점 타입/차선 정보는 API 미제공 → 모든 회전 스텝에서 팝업 표시

목적지 도착 팝업:
- 목적지까지 남은 거리 < 300m → 동일한 팝업 방식
- 중심 = 목적지 좌표 (고정)
- 정북 2D 탑뷰로 목적지 주변 + 진입로 명확 표시
- 목적지 마커 강조 표시
- 차량이 목적지를 향해 접근하는 모습이 리얼하게 보임
- 건물 밀집 지역에서 정확한 도착 위치와 진입 방향을 직관적으로 파악
- 도착 판정 시 팝업 닫기 + 도착 안내 화면 전환

구현:
- 별도 MKMapView 인스턴스 (메인 지도와 독립, 터치 비활성)
- SwiftUI overlay로 메인 NavigationView 위에 팝업 배치
- 팝업 크기: 화면 너비 60% × 높이 40% 정도
- 팝업 위치: 화면 좌하단 또는 우하단 (메인 안내 배너와 겹치지 않게)
- 페이드인/아웃 애니메이션 (0.3초)
```

---

## 4. 데이터 모델 (SwiftData)

### 4.1 FavoritePlace (즐겨찾기)

```
@Model
class FavoritePlace {
    var id: UUID
    var name: String           // "집", "회사", 사용자 지정 이름
    var address: String        // 도로명 주소
    var latitude: Double
    var longitude: Double
    var category: String       // home, work, custom
    var sortOrder: Int
    var createdAt: Date
    var lastUsedAt: Date
}
```

### 4.2 SearchHistory (검색 기록)

```
@Model
class SearchHistory {
    var id: UUID
    var query: String          // 검색어
    var placeName: String      // 선택한 장소명
    var address: String
    var latitude: Double
    var longitude: Double
    var searchedAt: Date
}
```

### 4.3 NavigationRecord (안내 기록)

```
@Model
class NavigationRecord {
    var id: UUID
    var originName: String
    var originLatitude: Double
    var originLongitude: Double
    var destinationName: String
    var destinationAddress: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var transportType: String      // automobile, walking
    var expectedDuration: TimeInterval
    var actualDuration: TimeInterval?
    var distance: Double
    var startedAt: Date
    var completedAt: Date?
    var wasCompleted: Bool
}
```

### 4.4 VehicleIcon (차량 아이콘 설정)

```
@Model
class VehicleIcon {
    var id: UUID
    var name: String               // 사용자 지정 이름 ("내 차")
    var type: String               // liftSubject, model3D, preset
    var imageData: Data?           // Lift Subject 결과 PNG
    var modelFileName: String?     // 3D 모델 파일명 (bundled or imported)
    var presetName: String?        // 프리셋 이름 ("sedan", "suv", "sport")
    var scale: Double              // 아이콘 크기 배율 (0.5 ~ 2.0)
    var isActive: Bool             // 현재 사용 중 여부
    var createdAt: Date
}
```

### 4.5 GPXRecording (GPS 녹화 기록)

```
@Model
class GPXRecording {
    var id: UUID
    var name: String               // 파일명 / 사용자 지정 이름
    var fileName: String           // 실제 GPX 파일명
    var originName: String         // 출발지 이름
    var destinationName: String    // 목적지 이름
    var duration: TimeInterval     // 총 주행 시간
    var distance: Double           // 총 주행 거리 (m)
    var pointCount: Int            // GPS 포인트 수
    var recordedAt: Date           // 녹화 시작 시간
}
```

---

## 5. 에러 처리

| 상황 | 대응 |
|------|------|
| GPS 신호 없음 | "GPS 신호를 찾고 있습니다" + 마지막 위치 유지 |
| 경로 탐색 실패 | "경로를 찾을 수 없습니다" + 재시도 버튼 |
| 네트워크 없음 | "네트워크 연결을 확인하세요" + 마지막 경로 유지 |
| 위치 권한 거부 | 설정 앱으로 이동 유도 |
| MKDirections 제한 | 자동 재시도 (exponential backoff) |
| 재경로 탐색 실패 | 기존 경로 유지 + 수동 재탐색 버튼 |

---

## 6. 권한 요구사항

| 권한 | 용도 | 필수 여부 |
|------|------|----------|
| Location When In Use | GPS 위치 추적 | 필수 |
| Location Always | 백그라운드 네비게이션 | 선택 (권장) |
| CarPlay Navigation | CarPlay 네비 기능 | CarPlay 사용 시 필수 |
| Audio Session | 음성 안내 출력 | 자동 (권한 불필요) |
| Background Modes | 위치 + 오디오 | Info.plist 설정 |

### Info.plist 필수 설정
```
- NSLocationWhenInUseUsageDescription
- NSLocationAlwaysAndWhenInUseUsageDescription
- UIBackgroundModes: [location, audio]
- UIApplicationSceneManifest: CarPlay scene configuration
```

---

## 7. 성능 요구사항

| 항목 | 목표 |
|------|------|
| 앱 시작 → 지도 표시 | < 1.5초 |
| 검색어 입력 → 자동완성 | < 300ms |
| 경로 탐색 요청 → 결과 | < 3초 |
| GPS 업데이트 → UI 반영 | < 100ms |
| 음성 안내 트리거 → 발화 | < 500ms |
| 메모리 사용량 (네비 중) | < 200MB |
| 배터리 소모 (1시간 네비) | < 15% |

---

## 8. 테스트 전략

| 테스트 유형 | 대상 | 도구 |
|------------|------|------|
| Unit Test | 경로 이탈 감지, 안내 타이밍, ETA 계산 | XCTest |
| UI Test | 검색 → 경로 → 안내 플로우 | XCUITest |
| Location Simulation | GPS 시뮬레이션 테스트 | Xcode GPX 파일 |
| CarPlay Test | CarPlay UI/안내 | Xcode CarPlay Simulator |
| 실차 테스트 | 실제 도로 주행 | 실기기 + CarPlay |
