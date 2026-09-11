# GPS 손실 처리 설계

## 1. 배경

정차 중 차량 아이콘이 회색으로 전환되는 문제 분석 결과, 두 가지 원인이 있었다.

1. **맵매칭 threshold 부족**: 정차 시 threshold=20m인데 GPS 노이즈가 21~22m → 매칭 실패
2. **GPS 손실 신호 처리 미흡**: 1.1초 이상 GPS 공백 시 합성 신호를 생성했으나, 이를 맵매칭에 활용하지 못함

---

## 2. GPS 손실 신호 (Synthetic GPS Loss Signal)

### 개요

`RealGPSProvider`는 1.1초 이상 iPhone GPS 응답이 없을 때 **합성 GPS 손실 신호**를 발행한다.

```
lastGPSReceivedTime 기준으로 1.1s 경과
    → handleTickTimeout() 발동
    → horizontalAccuracy=500 인 CLLocation 발행
    → 0.9s rate limit으로 연속 발행 제한
```

### 합성 CLLocation 구성

`handleTickTimeout()`이 생성하는 CLLocation은 `lastLocation`의 값을 최대한 보존한다.
좌표·속도·방향은 마지막 유효값을 유지하고, horizontalAccuracy만 sentinel 값(500)으로 교체:

```swift
CLLocation(
    coordinate:         lastLocation.coordinate,         // 마지막 유효 GPS 좌표
    altitude:           lastLocation.altitude,           // 마지막 유효 고도
    horizontalAccuracy: CLLocation.gpsLossAccuracy,      // 500 (합성 신호 식별자)
    verticalAccuracy:   lastLocation.verticalAccuracy,   // 마지막 유효 수직 정확도
    course:             lastLocation.course,             // 마지막 유효 방향
    speed:              lastLocation.speed,              // 마지막 유효 속도
    timestamp:          Date()                           // 현재 시각
)
```

---

## 3. GPS 유효성 판단

### CLLocation+Navigation.swift

```swift
static let gpsLossAccuracy: CLLocationAccuracy = 500

/// handleTickTimeout()이 생성한 합성 GPS 손실 신호
var isGPSLoss: Bool {
    horizontalAccuracy == Self.gpsLossAccuracy
}

/// 실제 iPhone GPS 유효 여부 (합성 신호 제외)
var isValid: Bool {
    horizontalAccuracy >= 0 && !isGPSLoss
}
```

### accuracy 값별 의미

| accuracy | isGPSLoss | isValid | 출처 |
|----------|-----------|---------|------|
| `< 0` (예: -1) | false | false | iPhone GPS fix 실패 (드묾) |
| `0~499` | false | true | 실제 iPhone GPS |
| `500` | **true** | false | 앱 합성 GPS 손실 신호 |

---

## 4. 맵매칭 처리

### 정책

| 상태 | 맵매칭 실행 | 근거 |
|------|------------|------|
| `isValid=true` | ✅ | 정상 GPS |
| `isGPSLoss=true` | ✅ | 마지막 위치로 매칭 유지 (파란색 아이콘) |
| 둘 다 false | ❌ | 완전 무효 GPS |

### NavigationEngine.resolveMatchedState

```swift
guard location.isValid || location.isGPSLoss else {
    // accuracy < 0 인 진짜 무효 GPS
    return MatchedState(..., isMatched: false, ...)
}
// isValid 또는 isGPSLoss → 맵매칭 실행
let matchResult = mapMatcher.match(location)
```

GPS 손실 상태에서도 맵매칭을 실행하여, 마지막 유효 위치 기반으로 매칭 성공 시 파란색 아이콘 유지.

---

## 5. GPS 약함 아이콘 (isGPSValid)

### 정책

`isGPSValid = location.isValid` — 합성 신호(500)는 `isValid=false`이므로 GPS 약함 아이콘 표시 대상.

현재 구현은 즉시 표시이나, 추후 N회 연속 후 표시로 개선 예정:

```
- isValid=false 1회: weaknessCount++
- weaknessCount > N 이후: GPS 약함 아이콘 표시
- isValid=true: weaknessCount=0 리셋
```

### isGPSValid 사용처

| 용도 | isGPSValid=true | isGPSValid=false |
|------|----------------|-----------------|
| raw GPS 점 표시 | 표시 | 숨김 |
| GPS 약함 아이콘 | 숨김 | 표시 |
| 차량 아이콘 색상 | `matched.isMatched` 기반 | `matched.isMatched` 기반 |

차량 아이콘 색상은 `isGPSValid`가 아닌 `matched.isMatched` 기반이므로, GPS 손실 시에도 맵매칭이 성공하면 파란색을 유지한다.

---

## 6. 맵매칭 거리 threshold

```swift
threshold = thresholdBase + speed * thresholdTimeFactor
//          35m          +  속도(m/s) × 1.0
```

`thresholdBase`를 20m → 35m으로 변경. 정차 시 GPS 노이즈(~22m)와 불량 GPS(~37m)를 커버.

| 상황 | threshold | 처리 |
|------|-----------|------|
| 정차 | 35m | 22m GPS 노이즈 통과 |
| 30km/h | 43.3m | |
| 60km/h | 51.7m | |
