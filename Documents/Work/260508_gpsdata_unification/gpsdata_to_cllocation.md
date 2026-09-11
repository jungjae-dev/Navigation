# GPSData 제거 — CLLocation 단일 타입으로 통일

작성일: 2026-05-08

---

## 1. 배경 / 문제점

현재 위치 정보를 두 가지 타입으로 관리하고 있다.

| 타입 | Publisher | 용도 |
|---|---|---|
| `CLLocation` | `locationPublisher` | 지도 표시, 녹화 등 UI |
| `GPSData` | `gpsPublisher` | 맵매칭 엔진 입력 |

`GPSData`는 아래 세 가지 목적으로 도입됐다.

1. **GPS 손실 신호** (`isValid: false`) — CLLocation에는 GPS 끊김 개념이 없어서
2. **heading 보존** (`lastValidCourse`) — 정지·저속 구간에서 직전 course 유지
3. **accuracy 필터** (`isAccurateForNavigation`) — 맵매칭용 100m 이내 필터

---

## 2. GPSData 제거가 가능한 이유

### 2.1 GPS 손실 신호 → `horizontalAccuracy = -1`

Apple이 이미 정의한 컨벤션이다.

- `horizontalAccuracy < 0` → 좌표 무효 (Apple 공식 스펙)
- `horizontalAccuracy >= 0` → 유효한 좌표

GPS 손실 타이머가 `horizontalAccuracy = -1`인 CLLocation을 발행하면 `isValid` 없이 동일하게 처리 가능하다.

### 2.2 `lastValidCourse` → 불필요

`lastValidCourse`는 원래 "compass가 엔진에 유입되는 것을 막기 위한" 장치였다. compass를 GPS 파이프라인에서 제거한 시점(`5874dd4`)부터 역할이 사라졌다.

현재 `MapMatcher`가 이미 `location.course < 0`이면 heading 검증을 스킵하므로, sticky 값 없이도 동작이 동일하다.

```swift
// MapMatcher.swift — 이미 처리됨
let skipHeadingCheck = transportMode == .walking
    || gps.speed < 1.4
    || gps.heading < 0   // ← course=-1 이면 검증 스킵
```

### 2.3 `isAccurateForNavigation` → 인라인 치환

```swift
// 기존
gps.isAccurateForNavigation

// 변경 후
0 <= location.horizontalAccuracy && location.horizontalAccuracy <= 100
```

---

## 3. 타입 매핑

| 기존 `GPSData` | 변경 후 `CLLocation` |
|---|---|
| `gps.isValid` | `location.horizontalAccuracy >= 0` |
| `gps.isAccurateForNavigation` | `0 <= location.horizontalAccuracy <= 100` |
| `gps.coordinate` | `location.coordinate` |
| `gps.heading` | `location.course` |
| `gps.speed` | `max(0, location.speed)` |
| `gps.timestamp` | `location.timestamp` |

---

## 4. Publisher 통합

`locationPublisher`와 `gpsPublisher`를 **`locationPublisher` 하나로 통합**한다.

모든 소비처가 동일한 CLLocation 스트림을 받고, 필요에 따라 처리한다.

- **UI (지도 표시, CarPlay 등)**: GPS 손실 신호(`horizontalAccuracy < 0`)를 받아도 마지막 좌표가 유지되므로 자연스럽게 무시됨
- **엔진 (`NavigationEngine`)**: `horizontalAccuracy < 0`이면 GPS 손실로 처리
- **녹화 (`LocationRecorder`)**: `.filter { $0.horizontalAccuracy >= 0 }`로 손실 신호 제외

> GPS 손실 CLLocation의 좌표는 `lastLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)`.
> `lastLocation`이 nil인 경우(GPS를 한 번도 수신하지 못한 상태)는 엔진이 아직 시작 전이므로 실질적으로 문제 없음.

---

## 5. 변경 파일 목록

### 삭제
- `Navigation/Engine/Model/GPSData.swift`

### 수정

| 파일 | 변경 내용 |
|---|---|
| `GPS/GPSProviding.swift` | `gpsPublisher` 제거, `locationPublisher` 타입 `CLLocation`으로 변경 |
| `GPS/RealGPSProvider.swift` | `gpsSubject` 제거, `lastValidCourse` 제거, GPS 손실 시 `horizontalAccuracy=-1` CLLocation 발행 |
| `GPS/FileGPSProvider.swift` | `gpsPublisher` 제거, `locationPublisher` 단일화 |
| `Engine/MapMatcher.swift` | `match(_ gps: GPSData)` → `match(_ location: CLLocation)` |
| `Engine/NavigationEngine.swift` | `tick(gps: GPSData)` → `tick(location: CLLocation)`, 필드 매핑 전환 |
| `Service/Location/LocationService.swift` | `gpsPublisher` 제거, `locationPublisher` 단일화 |
| `Coordinator/AppCoordinator.swift` | `gpsPublisher` 참조 → `locationPublisher` |
| `App/CarPlaySceneDelegate.swift` | `gpsPublisher` 참조 → `locationPublisher` |
| `Service/CarPlay/NavigationSessionManager.swift` | `gpsPublisher` 참조 → `locationPublisher` |
| `Service/Recording/LocationRecorder.swift` | GPS 손실 필터 추가 |
| `NavigationTests/*` | `GPSData` → `CLLocation` 교체 |
