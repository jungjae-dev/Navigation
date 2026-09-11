# 차량 아이콘 시스템 설계 문서

**작성일**: 2026-05-04  
**최종 업데이트**: 2026-05-04  
**대상 브랜치**: main (feature/29-map-matching-refactoring 머지 후)

---

## 1. 기능 개요

차량 아이콘은 세 가지 소스를 지원한다. 세 가지 중 **하나만** 활성화된다.

| 기능 | 설명 | OS 요구사항 |
|---|---|---|
| **프리셋** | 내장 SF Symbol 5종 (세단/SUV/스포츠카/트럭/오토바이) | iOS 15+ |
| **커스텀 사진** | 사진에서 피사체 추출 후 PNG 저장 | iOS 17+ (Vision) |
| **3D 차량 모델** | 사용자 USDZ 임포트 → Live SCNView 렌더링 | iOS 15+ (SceneKit) |

---

## 2. 시스템 구조

### 2.1 VehicleIconSource 모델

```swift
enum VehicleIconSource: Equatable {
    case preset(VehiclePreset)   // SF Symbol
    case custom(String)          // filename in Documents
    case model3D(String)         // USDZ filename in Documents
}

enum VehiclePreset: String, CaseIterable {
    case sedan, suv, sportsCar, truck, motorcycle
    var iconName: String   // SF Symbol name
    var displayName: String
}
```

### 2.2 아키텍처 레이어

```
[Settings UI]
  SettingsViewController  (소스 선택기: 프리셋 / 커스텀 사진 / 3D 모델)
  SettingsViewModel
        │
        ▼
[Domain Service]
  VehicleIconService (singleton)
  ├─ iconSourcePublisher: CurrentValueSubject<VehicleIconSource, Never>
  ├─ selectedPresetPublisher: CurrentValueSubject<VehiclePreset, Never>
  ├─ selectPreset(_:)
  ├─ setCustomImage(_:) → Documents/vehicle_custom_icon.png
  ├─ setModel3D(fileURL:rotationSteps:) → Documents/vehicle_3d_model.usdz
  └─ currentVehicleImage(size:) → UIImage?   (preset/custom 전용, model3D 시 nil)

[Vision (iOS 17+)]
  LiftSubjectService
  ├─ liftSubject(from:) → UIImage (배경 제거)
  PhotoPickerHelper
  └─ pickImage(from:completion:)

[3D Import]
  UIDocumentPickerViewController (USDZ 선택)
  Vehicle3DImportViewController  (회전 보정 UI)
  └─ rotationSteps: Int  →  UserDefaults("vehicle_3d_rotation_steps")

[Map Rendering]
  MapViewController (홈/검색)
  └─ VehicleAnnotation → VehicleIconService.currentVehicleImage() ✅
                        → 자동추적 모드 + model3D → Vehicle3DAnnotationView

  NavigationViewController (주행)
  └─ vehicleAnnotation → VehicleIconService.currentVehicleImage() (Phase 1)
                        → 자동추적 모드 + model3D → Vehicle3DAnnotationView (Phase 2)
```

### 2.3 데이터 흐름 (목표)

```
사용자 설정 변경
        │
        ▼
VehicleIconService.iconSourcePublisher
        │
        ├──► SettingsViewController: 셀 UI 갱신
        │
        ├──► MapViewController: annotation 뷰 즉시 갱신
        │
        └──► NavigationViewController: 아이콘 즉시 갱신
```

---

## 3. 현재 구현 상태 진단

### 3.1 프리셋

| 위치 | 구현 | 비고 |
|---|---|---|
| Settings UI | ✅ 액션시트 선택, 즉시 반영 | |
| UserDefaults 저장 | ✅ `settings_vehicle_preset` | |
| 홈/검색 화면 `MapViewController` | ✅ `currentVehicleImage()` 사용 | |
| **주행 화면 `NavigationViewController`** | ❌ `location.north.fill` 하드코딩 | **미연결** |
| 설정 변경 시 주행 중 즉시 갱신 | ❌ 구독 없음 | |

### 3.2 커스텀 사진

| 위치 | 구현 | 비고 |
|---|---|---|
| PHPicker 사진 선택 | ✅ | |
| Vision 배경 제거 (iOS 17+) | ✅ `VNGenerateForegroundInstanceMaskRequest` | |
| 미리보기 → 저장 | ✅ `Documents/vehicle_custom_icon.png` | |
| 홈/검색 화면 렌더링 | ✅ | |
| **주행 화면 렌더링** | ❌ 하드코딩 동일 | **미연결** |
| iOS 16 이하 fallback | ✅ 배경 제거 없이 원본 사용 | |

### 3.3 3D 차량 모델

| 위치 | 구현 | 비고 |
|---|---|---|
| Settings 토글 | ✅ 저장만 됨 (구 구조) | **설정 UI 변경 필요** |
| **실제 3D 렌더링** | ❌ 코드 없음 | **미구현** |
| USDZ 임포트 | ❌ 없음 | |
| 회전 보정 UI | ❌ 없음 | |

---

## 4. 목표 설계

### 4.1 Phase 1 — 프리셋 / 커스텀 사진 주행 화면 연결

#### 변경 목표
- `NavigationViewController` 도 `VehicleIconService` 를 구독
- 설정 변경 시 주행 중에도 즉시 아이콘 갱신
- 아이콘 rotation 로직은 기존 displayLink 방식 유지

#### 컴포넌트 설계

```swift
// NavigationViewController

private var vehicleIconCancellable: AnyCancellable?

// viewDidLoad / bind() 에서
vehicleIconCancellable = VehicleIconService.shared.iconSourcePublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.refreshVehicleAnnotationImage()
    }

private func refreshVehicleAnnotationImage() {
    guard let view = mapView.view(for: vehicleAnnotation) else { return }
    let image = VehicleIconService.shared.currentVehicleImage(size: 28)
        ?? UIImage(systemName: "location.north.fill")?
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
    view.image = image
}

// viewFor annotation 에서도 iconService 참조
func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    if annotation === vehicleAnnotation {
        let image = VehicleIconService.shared.currentVehicleImage(size: 28)
            ?? UIImage(systemName: "location.north.fill")...
        view.image = image
    }
}
```

---

### 4.2 Phase 2 — 3D 차량 모델

#### USDZ 임포트 흐름

```
1. 설정 > 차량 아이콘 > 3D 모델 > 파일 가져오기
2. UIDocumentPickerViewController (UTType.usdz 필터)
3. Vehicle3DImportViewController 표시
   ├── SCNView 미리보기 (Live 렌더링)
   └── ↺ ↻ 버튼 (90° 단위 회전 조정)
4. 확인
   ├── Documents/vehicle_3d_model.usdz 저장
   └── UserDefaults("vehicle_3d_rotation_steps") 저장 (0~3)
5. VehicleIconService.setModel3D(fileURL:rotationSteps:) 호출
   → iconSourcePublisher(.model3D) 발행
```

#### 렌더링 방식 — Live SCNView

MapKit 의 `MKAnnotationView` 에 `SCNView` 를 subview 로 추가하여 실시간 렌더링:

```
MKAnnotationView
  └── SCNView (투명 배경, isUserInteractionEnabled = false)
        └── SCNScene
              └── 차량 노드 (rotationSteps 적용 + heading Y축 회전)
```

> **MapKit 3D 연동 한계**: MKAnnotationView 는 MapKit 의 perspective transform 과 독립된 2D screen-space 요소.
> 지도 카메라 pitch 변경과 SCNView 내부 카메라를 완벽하게 동기화하는 공식 API 없음.
> Google Maps / Waze / Apple Maps 모두 동일한 한계로 2D 아이콘을 사용함.
> → 자동추적 모드 한정 적용으로 이 문제를 우회.

#### 자동추적 / 수동 모드 분기

```
자동추적 모드 (isAutoTracking = true) + model3D 활성화
  → Vehicle3DAnnotationView.sceneView.isHidden = false
  → NavigationCameraHelper 고정 pitch → SCNView 카메라 pitch 고정 일치
  → 항상 올바른 시점 유지

수동 모드 (isAutoTracking = false, 사용자 지도 터치)
  → Vehicle3DAnnotationView.sceneView.isHidden = true
  → annotationView.image = 2D 아이콘 (자동 노출)
```

모드 전환 시 `annotationView.image` (2D) 와 `sceneView` (3D) 중 하나만 보이는 구조로, 2D 아이콘은 항상 준비된 상태이며 3D 가 그 위를 덮는다.

#### Vehicle3DAnnotationView 설계

```swift
final class Vehicle3DAnnotationView: MKAnnotationView {

    private let sceneView = SCNView()
    private var vehicleNode: SCNNode?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        sceneView.backgroundColor = .clear
        sceneView.isUserInteractionEnabled = false
        sceneView.frame = bounds
        addSubview(sceneView)
    }

    func loadModel(fileURL: URL, rotationSteps: Int) {
        guard let scene = try? SCNScene(url: fileURL) else { return }
        vehicleNode = scene.rootNode
        vehicleNode?.eulerAngles.y = Float(rotationSteps) * (.pi / 2)
        sceneView.scene = scene
        sceneView.pointOfView?.eulerAngles.x = -Float(NavigationCameraHelper.defaultPitch * .pi / 180)
    }

    var heading: CLLocationDirection = 0 {
        didSet {
            let baseRotation = Float(rotationSteps) * (.pi / 2)
            vehicleNode?.eulerAngles.y = baseRotation + Float(heading * .pi / 180)
        }
    }

    var is3DVisible: Bool = false {
        didSet { sceneView.isHidden = !is3DVisible }
    }
}
```

#### CarPlay

CarPlay 도 동일 방식 적용:
- `CPMapTemplate` + `MKMapView` 구조에서 `MKAnnotationView` 렌더링 동일하게 동작
- 자동추적 / 수동 모드 구분 로직 동일하게 적용
- CarPlay 별도 분기 없음

#### 설정 UI 변경 — 소스 선택기

기존 "3D 차량 모델" 토글 제거. 세 가지 소스를 단일 선택 목록으로 통합:

```
차량 아이콘
  ├── ● 프리셋           → 세단 / SUV / 스포츠카 / 트럭 / 오토바이
  ├── ○ 커스텀 사진      → PHPicker + Vision 배경 제거
  └── ○ 3D 모델          → USDZ 가져오기 (미등록 시 "파일 없음" 표시)
```

세 가지 중 하나만 활성화. `VehicleIconSource` enum 이 단일 진실 소스.

---

## 5. 시나리오별 동작 정의

### 시나리오 A: 프리셋 변경 (주행 중)

```
1. 설정 > 차량 아이콘 > 세단 → SUV 선택
2. VehicleIconService.selectPreset(.suv) 호출
3. iconSourcePublisher 발행
4. NavigationViewController 구독 수신
   → refreshVehicleAnnotationImage() 호출
   → mapView.view(for: vehicleAnnotation)?.image = SUV 이미지
5. 아이콘 즉시 교체 (딜레이 없음)
```

### 시나리오 B: 커스텀 사진 적용 (주행 전)

```
1. 설정 > 차량 아이콘 > 커스텀 사진 선택
2. PHPicker → 사진 선택
3. iOS 17+: Vision 배경 제거 → 미리보기
   iOS 16-: 원본 이미지 → 미리보기
4. 확인 → VehicleIconService.setCustomImage(cutout)
   → Documents/vehicle_custom_icon.png 저장
5. iconSourcePublisher(.custom) 발행
6. 주행 시작 → NavigationViewController viewFor 에서 커스텀 이미지 사용
```

### 시나리오 C: 3D 모델 임포트 및 주행

```
1. 설정 > 차량 아이콘 > 3D 모델 > 파일 가져오기
2. UIDocumentPickerViewController → USDZ 선택
3. Vehicle3DImportViewController
   → SCNView 미리보기
   → 회전 버튼으로 방향 조정
   → 확인
4. Documents/vehicle_3d_model.usdz 저장
   + rotationSteps UserDefaults 저장
5. iconSourcePublisher(.model3D) 발행
6. 주행 시작
   → isAutoTracking = true → sceneView 표시 (3D)
7. 사용자 지도 터치
   → isAutoTracking = false → sceneView hide → 2D 아이콘 노출
8. 재중심 버튼 탭
   → isAutoTracking = true → sceneView 재표시
```

### 시나리오 D: heading 변경 (주행 중, 3D 모드)

```
1. displayLink 에서 heading 값 계산
2. NavigationViewController → vehicleAnnotationView.heading = newHeading
3. Vehicle3DAnnotationView
   → vehicleNode.eulerAngles.y = rotationOffset + headingRad
4. SCNView 즉시 반영 (애니메이션 없음)
```

---

## 6. 구현 계획

### Phase 1 — 프리셋/커스텀 사진 주행 화면 연결 (소 작업)

| 작업 | 파일 | 설명 |
|---|---|---|
| `viewFor` 에서 VehicleIconService 참조 | NavigationViewController | 하드코딩 제거 |
| iconSourcePublisher 구독 + 즉시 갱신 | NavigationViewController | Combine 구독 |
| MapViewController 구독 추가 | MapViewController | 설정 변경 즉시 반영 |

### Phase 2 — 3D 차량 모델 (중 작업)

| 작업 | 설명 |
|---|---|
| `VehicleIconSource.model3D` 케이스 추가 | VehicleIconService |
| `Vehicle3DAnnotationView` 구현 | SCNView 내장, heading/is3DVisible 프로퍼티 |
| `Vehicle3DImportViewController` 구현 | USDZ 미리보기 + 회전 UI |
| `UIDocumentPickerViewController` 연동 | USDZ 파일 선택 |
| NavigationViewController 3D/2D 분기 | isAutoTracking 변경 시 sceneView show/hide |
| MapViewController 3D/2D 분기 | 동일 |
| Settings UI 소스 선택기로 교체 | 기존 토글 제거 |

### 의존성

```
Phase 1 → Phase 2 순서 권장
(Phase 1 에서 iconSourcePublisher 구독 구조를 정립하면
 Phase 2 에서 model3D 케이스만 추가하면 됨)
```

---

## 7. 파일 변경 예상 목록

### Phase 1

| 파일 | 변경 내용 |
|---|---|
| `NavigationViewController.swift` | viewFor VehicleIconService 참조, iconSourcePublisher 구독, refreshVehicleAnnotationImage() |
| `MapViewController.swift` | iconSourcePublisher 구독 → annotation 뷰 즉시 갱신 |

### Phase 2

| 파일 | 변경/신규 |
|---|---|
| `Vehicle3DAnnotationView.swift` | **신규** — SCNView 내장 annotation 뷰 |
| `Vehicle3DImportViewController.swift` | **신규** — USDZ 미리보기 + 회전 UI |
| `VehicleIconSource.swift` (또는 VehicleIconService.swift) | model3D 케이스 추가 |
| `VehicleIconService.swift` | setModel3D(fileURL:rotationSteps:) 추가 |
| `SettingsViewController.swift` | 소스 선택기 UI 로 교체, 토글 제거 |
| `NavigationViewController.swift` | 자동추적/수동 모드 시 sceneView show/hide |
| `MapViewController.swift` | 동일 |

---

## 8. 미결 사항

1. **SCNView 투명 배경**: `scene.background.contents = UIColor.clear` 적용 확인 필요
2. **CarPlay 실기 검증**: SCNView 가 CarPlay 외부 화면에서 정상 렌더링되는지 테스트 필요
3. **USDZ 없는 상태에서 model3D 선택 시 UX**: "파일 없음 — 파일 가져오기" 안내 or 선택 즉시 picker 열기
