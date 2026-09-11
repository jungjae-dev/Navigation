# 맵매칭 개선 작업

## 진행 예정

### 1. CLLocation / CLLocationCoordinate2D Extension 공통화
**신규 파일:** `CLLocation+Navigation.swift`, `CLLocationCoordinate2D+Geometry.swift`

#### 1-1. CLLocation — accuracy / course 체크
현재 `RealGPSProvider`, `LocationService`, `OffRouteDetector`, `UserLocationPresenter` 등에 accuracy 체크가 산재.

```swift
extension CLLocation {
    static let navigationAccuracyThreshold: CLLocationAccuracy = 100

    /// 기본화면 표시용 — 유효한 좌표면 사용 (accuracy >= 0)
    var isValidForDisplay: Bool {
        horizontalAccuracy >= 0
    }

    /// 주행 맵매칭용 — accuracy 100m 이내
    var isValidForNavigation: Bool {
        horizontalAccuracy >= 0 && horizontalAccuracy <= Self.navigationAccuracyThreshold
    }

    /// GPS course 유효 여부
    var hasValidCourse: Bool {
        course >= 0
    }
}
```

적용 위치:

| 파일 | 변경 전 | 변경 후 |
|------|---------|---------|
| `RealGPSProvider` | `accuracy >= 0 && <= 100` (복잡한 조건) | `location.isValidForNavigation` / `location.isValidForDisplay` |
| `LocationService` | `accuracy >= 0 && <= 100` | `location.isValidForDisplay` |
| `OffRouteDetector` | `gpsAccuracy > 120` | `gpsAccuracy > CLLocation.navigationAccuracyThreshold` |
| `UserLocationPresenter` | `accuracy >= 0` | `location.isValidForDisplay` |

#### 1-2. CLLocationCoordinate2D — distance
현재 `MapMatcher`, `OffRouteDetector`, `RouteTracker`, `DistanceCalculator` 등 6곳에 동일 패턴 중복.

```swift
extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
```

#### 1-3. CLLocationCoordinate2D — interpolation
현재 `LocationInterpolator`, `LocationSimulator`, `VirtualDriveEngine` 등 4곳에 동일 패턴 중복.

```swift
extension CLLocationCoordinate2D {
    func interpolated(to other: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:  latitude  + (other.latitude  - latitude)  * t,
            longitude: longitude + (other.longitude - longitude) * t
        )
    }
}
```

#### 1-4. bearing — MapGeometry 통일
`MapMatcher`, `LocationSimulator`, `VirtualDriveEngine`이 `bearing(from:to:)`를 각자 재구현 중.
`MapGeometry.bearing(from:to:)` 사용으로 통일.

---

### 2. accuracy 불량 GPS 맵매칭 제외
**파일:** `NavigationEngine.resolveMatchedState()`

약한 accuracy = 터널 상황과 동일하게 처리.

```swift
private func resolveMatchedState(gps: GPSData) -> MatchedState {
    guard gps.isValid else { ... }

    // accuracy 불량 → 맵매칭 스킵 (터널과 동일 처리)
    guard gps.accuracy <= CLLocation.navigationAccuracyThreshold else {
        if let lastPos = lastMatchedPosition {
            return MatchedState(position: lastPos,
                                heading: bearingAtSegment(mapMatcher.currentSegmentIndex),
                                isMatched: false, isOffRoute: false)
        }
        return MatchedState(position: gps.coordinate, heading: gps.heading,
                            isMatched: false, isOffRoute: false)
    }

    let matchResult = mapMatcher.match(gps)
    ...
}
```

| 상황 | 처리 | 아이콘 |
|------|------|--------|
| GPS 손실 (`isValid: false`) | 맵매칭 스킵, `lastMatchedPosition` 유지 | 회색 |
| accuracy > 100m | 맵매칭 스킵, `lastMatchedPosition` 유지 | 회색 |
| 정상 GPS | 맵매칭 진행 | 파랑 / 회색 |

---

### 3. 기본화면 GPS 필터 완화
**파일:** `LocationService.didUpdateLocations`, `RealGPSProvider`

```swift
// LocationService — locationPublisher 상한 제거
// 변경 전: accuracy >= 0 && <= 100
// 변경 후: accuracy >= 0 (location.isValidForDisplay)

// RealGPSProvider — locationSubject / gpsSubject 분리
// locationSubject → isValidForDisplay (기본화면용)
// gpsSubject      → isValidForNavigation (엔진용)
```

| Publisher | 기준 | 사용처 |
|-----------|------|--------|
| `locationPublisher` | accuracy ≥ 0 | 기본화면 위치 표시 |
| `gpsPublisher` | accuracy 0~100m | 주행 엔진 (맵매칭) |


---

### 4. 위치 표시 1초 지연 문제 및 예측 보간 개선

#### 4-1. 현재 구조와 문제

**흐름:**
```
GPS (1Hz)
  → NavigationEngine.tick()
    → MapMatcher → matchedPosition (G_n)
      → NavigationGuide → interpolator.setTarget(G_n)
        → CADisplayLink (60fps) → interpolator.interpolate()
          → vehicleAnnotation.coordinate
```

**LocationInterpolator 동작:**
```
G2 수신(T-1): previous = G1, target = G2  →  1초 동안 G1→G2 보간
G3 수신(T):   previous = G2, target = G3  →  1초 동안 G2→G3 보간
```

- G3 수신 시점에 아이콘은 G2 위치에서 시작
- G3 위치에 도달하는 데 1초 소요
- **아이콘은 항상 1 GPS 사이클(1초) 뒤처짐**

| 속도 | 1초 이동거리 | 시각적 지연 |
|------|------------|-----------|
| 30 km/h | ~8m | 항상 8m 뒤 |
| 60 km/h | ~17m | 항상 17m 뒤 |
| 100 km/h | ~28m | 항상 28m 뒤 |

**갈림길 문제:**
- G3 수신 시 아이콘은 G2에서 출발해 G3를 직선으로 향함
- 갈림길에서 G2(분기 전) → G3(Road A 진입) 구간을 직선 보간하면 Road B 방향을 순간 가리킴
- 약 1~2초 동안 아이콘이 엉뚱한 위치에 표시됨

---

#### 4-2. 개선 방안: 1초 예측 위치를 target으로 사용

**핵심 아이디어:**
G3 수신 시 target을 G3(현재)가 아닌 **G4'(1초 후 예측 위치)**로 설정.

```
현재: previous=G2, target=G3  →  T+1초에 G3 도달 (1초 지연)
개선: previous=G2, target=G4' →  T+0.5초에 아이콘 ≈ G3 (현재 위치와 일치)
```

```
T+0:   아이콘 = G2
T+0.5: 아이콘 ≈ G3  ← 실제 현위치와 일치
T+1:   아이콘 = G4' (예측)
T+1:   G4 실제 수신 → G4' ≈ G4 이면 jump 없음
```

**예측 거리 계산:**
```swift
// G3.speed × 1초 = 다음 1초 예상 이동거리
let predictDistance = location.safeSpeed * 1.0
```

- `CLLocation.speed`는 GPS 도플러 기반으로 위치 노이즈와 무관하게 정확
- `observedDistance`(G2→G3 거리) 대신 현재 속도 사용 → 더 직접적인 미래 예측값

**예측 위치 계산 (MapMatcher에 추가):**
```swift
func predictPosition(
    from coordinate: CLLocationCoordinate2D,
    segmentIndex: Int,
    distance: CLLocationDistance
) -> CLLocationCoordinate2D {
    guard distance > 0 else { return coordinate }

    var remaining = distance
    var current = coordinate
    var idx = segmentIndex

    while remaining > 0, idx < polyline.count - 1 {
        let segEnd = polyline[idx + 1]
        let distToEnd = current.distance(to: segEnd)
        if remaining <= distToEnd {
            return current.interpolated(to: segEnd, t: remaining / distToEnd)
        }
        remaining -= distToEnd
        current = segEnd
        idx += 1
    }
    return current
}
```

폴리라인을 따라 걷기 때문에 갈림길에서도 올바른 도로 위에서 예측 가능.

---

#### 4-3. 가드 조건

**조건 1: isMatched == false**
- 도로 위 위치를 특정할 수 없는 상태에서 예측 불가
- `lastMatchedPosition` 그대로 유지

**조건 2: 속도 급변 (가속·감속)**

`G3.speed × 1.0`은 다음 1초도 현재 속도가 유지된다고 가정. 속도 변화 시 오차 발생.

| 상황 | 문제 |
|------|------|
| 감속 (신호등) | 예측이 실제보다 앞 → 아이콘이 교차로 안으로 오버슈트 후 스냅백 |
| 가속 (출발) | 예측이 실제보다 짧음 → 아이콘이 뒤처짐 (오버슈트보단 양호) |

**대응: `min(lastSpeed, currentSpeed) × 1.0` 사용**

직전 속도(`lastSpeed`)와 현재 속도 중 작은 값으로 예측 → 항상 보수적으로 예측.

```swift
let predictSpeed = min(lastSpeed, location.safeSpeed)
let predictDistance = predictSpeed * 1.0
```

| 상황 | lastSpeed | currentSpeed | predictDistance | 효과 |
|------|---------|-------------|----------------|------|
| 등속 60 | 16.7 | 16.7 | 16.7m | 정확 ✓ |
| 감속 60→30 | 16.7 | 8.3 | 8.3m | 오버슈트 완화 ✓ |
| 급정거 60→0 | 16.7 | 0 | 0m | 예측 없음, 안전 ✓ |
| 가속 0→60 | 0 | 16.7 | 0m | lag 있지만 안전 ✓ |

---

#### 4-4. 구현 범위

| 파일 | 변경 내용 |
|------|---------|
| `MapMatcher` | `predictPosition(from:segmentIndex:distance:)` 추가 |
| `NavigationEngine` | `lastSpeed` 저장, 예측 좌표 계산 후 `MatchedState.position`에 적용 |
| `MatchResult` | 변경 없음 (라우팅 로직 영향 없음) |
| `LocationInterpolator` | 변경 없음 |
| `NavigationGuide` | 변경 없음 |

**NavigationEngine 변경 핵심:**
```swift
// resolveMatchedState 내부
if matchResult.isMatched {
    let predictSpeed = min(lastSpeed, location.safeSpeed)
    let predictDistance = predictSpeed * 1.0
    let displayPosition = mapMatcher.predictPosition(
        from: matchResult.coordinate,
        segmentIndex: matchResult.segmentIndex,
        distance: predictDistance
    )
    lastMatchedPosition = matchResult.coordinate  // 라우팅용: 실제 위치
    lastSpeed = location.safeSpeed                // 다음 예측용
    return MatchedState(position: displayPosition, ...)  // 표시용: 예측 위치
}
// isMatched == false → lastMatchedPosition 유지, 예측 없음
```

- `MatchResult.coordinate`: 실제 스냅 위치 (OffRouteDetector, RouteTracker 영향 없음)
- `MatchedState.position`: 예측 위치 (화면 표시, NavigationGuide.matchedPosition 용도)

---

#### 4-5. 남는 한계: 직선 보간

`LocationInterpolator.interpolate()`는 변경하지 않으므로 화면에 표시되는 이동 경로는 여전히 직선이다.

```swift
// 변경 없음
let coordinate = previous.interpolated(to: target, t: t)  // 직선
```

`previous`와 `target`이 모두 폴리라인 위에 있더라도, 두 점 **사이를 지나는 표시 경로**는 직선이다.
도로가 이 구간에서 꺾이면 아이콘이 코너를 가로질러 건물을 통과하는 것처럼 보인다.

---

**코너 구간 예시:**

```
도로: ——G2——[코너]——G3——G4——
```

**현재 방식 (예측 없음):**
```
G3 수신 시: previous ≈ G2, target = G3
  → G2(코너 전) → G3(코너 후) 직선 = 코너 shortcut 발생
  → 차량이 이미 돌았는데 아이콘이 코너를 가로지름 (이동 후 발생)
```

**예측 방식:**
```
G2 수신 시: previous ≈ G1, target = G3'예측(폴리라인 따라 코너 후)
  → G1(코너 전) → G3'(코너 후) 직선 = 코너 shortcut 발생
  → 차량이 아직 코너에 도달 전인데 아이콘이 먼저 지나침 (이동 전 발생)

G3 수신 시: previous ≈ G3, target = G4'예측
  → G3 → G4 직선 = 코너 이후 직선 구간, shortcut 없음 ✓
```

shortcut의 **크기는 동일**하나 **발생 타이밍이 1 GPS 사이클 앞으로** 당겨진다.

| | 현재 방식 | 예측 방식 |
|--|---------|---------|
| shortcut 발생 시점 | 코너 통과 **이후** (G3 수신 시) | 코너 도달 **이전** (G2 수신 시) |
| 시각적 느낌 | 차량이 돌았는데 아이콘이 엉뚱한 방향 | 아이콘이 살짝 앞서 코너를 미리 지남 |
| 어느 쪽이 덜 이상한가 | 진행 방향과 반대로 보임 (더 어색) | 진행 방향으로 앞서 보임 (덜 어색) |

---

**근본 해결: 폴리라인 따라 표시 보간 (향후 개선)**

`LocationInterpolator`가 폴리라인을 알고, 두 점 사이를 직선 대신 폴리라인 세그먼트를 따라 이동하면 shortcut이 완전히 제거된다.

```swift
// 향후 개선 방향
let coordinate = walkAlongPolyline(from: previous, to: target, t: t, polyline: polyline)
```

단, 이를 위해 `LocationInterpolator`에 폴리라인 전달이 필요하고 구조 변경이 수반된다.
현재 개선(4-2~4-4)으로 1초 지연 문제를 먼저 해결하고, 코너 shortcut은 이후 단계로 분리한다.
