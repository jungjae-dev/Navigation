# MapMatcher 개선 구현 계획

대상 파일: `Navigation/Engine/MapMatcher.swift`, `Navigation/Engine/NavigationLogger.swift`  
참고 문서: `mapmatcher_heading_scoring.md`

---

## 로그 형식 변경 계획

각 Phase 검증을 로그로 확인하기 위해 `[Match]` 라인에 `score=` 필드를 추가한다.

**현재:**
```
[Match] ✅ coord=(37.570768, 126.818748) seg=9 dist=3.9m Δ=4.2°
```

**변경 후:**
```
[Match] ✅ coord=(37.570768, 126.818748) seg=9 dist=3.9m Δ=4.2° score=4.2
```

### 구현 방법

1. `MatchResult`에 `score: Double` 필드 추가
2. `MapMatcher.match()` 에서 선택된 세그먼트의 score를 `MatchResult`에 포함
3. `NavigationLogger.logMatch()` 에서 `score=` 출력

---

## Phase 1: Backward Search 제거

### 변경 내용

`match()` 내부의 backward 탐색 루프 전체 제거.  
forward 탐색 결과를 곧바로 best로 사용.

```swift
// 제거 대상
var bwdProjection = coordinate
var bwdDistance: CLLocationDistance = .infinity
...
for i in stride(from: currentSegmentIndex - 1, through: 0, by: -1) { ... }
if fwdDistance <= bwdDistance { ... } else { ... }
```

### 로그 검증

직진 구간 로그에서 아래 패턴이 유지되는지 확인:

```
[Match] ✅ coord=(...) seg=3 dist=2.8m Δ=1.2° score=2.8
[Match] ✅ coord=(...) seg=3 dist=3.1m Δ=1.5° score=3.1
[Match] ✅ coord=(...) seg=4 dist=2.5m Δ=0.8° score=2.5   ← seg 전진
[Match] ✅ coord=(...) seg=4 dist=2.9m Δ=1.1° score=2.9
```

**확인 항목:**
- [ ] `✅` 연속 출력 (❌ 없음)
- [ ] `seg=` 번호가 단조 증가 (역방향 점프 없음)
- [ ] `[Reroute]` 미출력

---

## Phase 2: 탐색 종료 조건 개선

### 변경 내용

`distance > prevDist` 즉시 break → **threshold 초과 연속 3회** 시 break.

```swift
// 변경 전
} else if distance > prevDist {
    break
}
prevDist = distance

// 변경 후
if distance > threshold {
    consecutiveOverThreshold += 1
    if consecutiveOverThreshold > 3 { break }
    continue
}
consecutiveOverThreshold = 0
```

### 로그 검증

우회전 구간에서 아래 패턴으로 변화 확인:

**변경 전 (문제):**
```
[Match] ✅ coord=(...) seg=9 dist=4.3m Δ=4.2°
[Match] ✅ coord=(...) seg=9 dist=9.4m Δ=80.1°
[Match] ❌ coord=(...) seg=9 dist=11.6m Δ=112.9°   ← seg=9 고착
[Match] ❌ coord=(...) seg=9 dist=15.7m Δ=115.8°
[Reroute] ❌ off-route confirmed
```

**변경 후 (기대):**
```
[Match] ✅ coord=(...) seg=9  dist=4.3m  Δ=4.2°   score=4.5
[Match] ✅ coord=(...) seg=9  dist=9.4m  Δ=80.1°  score=...
[Match] ✅ coord=(...) seg=10 dist=14.8m Δ=3.2°   score=15.3  ← seg 전환
[Match] ✅ coord=(...) seg=10 dist=12.1m Δ=2.8°   score=12.6
```

**확인 항목:**
- [ ] 우회전 완료 직후 `seg=` 번호가 새 도로 세그먼트로 전환됨
- [ ] 전환 후 `✅` 유지 (❌ 미발생)
- [ ] `[Reroute]` 미출력

---

## Phase 3: 세그먼트 선택 기준 → 최소 Score

### 변경 내용

최소 거리 선택 → 최소 score 선택. `headingWeight = 30` 적용.

```swift
private let headingWeight: CLLocationDistance = 30

let delta = skipHeadingCheck ? 0 : abs(MapGeometry.angleDelta(course, segHeading))
let score = distance + (delta / 180.0) * headingWeight

if score < bestScore {
    bestScore = score
    ...
}
```

### 로그 검증

우회전 전후 score 변화로 선택 근거 확인:

```
// 회전 진입 전: seg=9 거리·heading 모두 양호
[Match] ✅ coord=(...) seg=9 dist=4.3m Δ=4.2° score=5.0

// 회전 중: seg=9 Δ 커지면서 score 증가
[Match] ✅ coord=(...) seg=9 dist=9.4m Δ=80.1° score=22.8

// 회전 완료: seg=10이 score 우세로 선택
[Match] ✅ coord=(...) seg=10 dist=14.8m Δ=3.2° score=15.3
//           seg=9는: dist=11.6m Δ=112° score=30.3  → 탈락
```

**확인 항목:**
- [ ] 회전 전: `score ≈ dist` (Δ 작아서 패널티 미미)
- [ ] 회전 완료 후: `seg=` 가 새 도로로 전환되고 `Δ=` 값이 작아짐 (10° 이하)
- [ ] `[Reroute]` 미출력

저속/course 미확보 시 headingWeight=0 동작 확인:
```
// speed < 5km/h → score = dist (heading 패널티 없음)
[Match] ✅ coord=(...) seg=5 dist=3.1m Δ=45.0° score=3.1
//                                                       ↑ dist와 동일
```

**확인 항목:**
- [ ] 저속 구간에서 `score = dist` (Δ 무시됨)

---

## Phase 4: maxAngleDelta 하드컷 제거

### 변경 내용

90° 하드컷 제거. 거리 threshold 초과만 매칭 실패 처리.

```swift
// 제거 대상
private let maxAngleDelta: CLLocationDirection = 90

if !skipHeadingCheck && headingDelta > maxAngleDelta {
    return MatchResult(isMatched: false, ...)
}
```

### 로그 검증

유턴 구간 로그 확인:

**변경 전 (문제):**
```
[Match] ❌ coord=(...) seg=5 dist=8.0m Δ=178.2°   ← Δ > 90° 하드컷
[Match] ❌ coord=(...) seg=5 dist=9.1m Δ=179.0°
[Reroute] ❌ off-route confirmed
```

**변경 후 (기대):**
```
// 유턴 중
[Match] ✅ coord=(...) seg=5  dist=8.0m  Δ=178.2° score=37.7  ← 진입로(score 높음)
// 유턴 완료 → 역방향 세그먼트 선택
[Match] ✅ coord=(...) seg=12 dist=11.5m Δ=1.8°   score=11.8  ← 역방향 도로
[Match] ✅ coord=(...) seg=12 dist=9.2m  Δ=2.1°   score=9.6
```

**확인 항목:**
- [ ] 유턴 완료 후 `✅` 전환 (❌ 미발생)
- [ ] 전환된 `seg=` 의 `Δ=` 값이 0°에 가까움
- [ ] `[Reroute]` 미출력

실제 경로 이탈 시 재탐색 정상 트리거 확인:
```
[Match] ❌ coord=(...) seg=5 dist=38.2m Δ=45.0° score=45.7  ← dist > threshold
[Match] ❌ coord=(...) seg=5 dist=41.5m Δ=47.0° score=49.3
[Reroute] ❌ off-route confirmed consecutiveFailures=3        ← 정상 트리거
```

**확인 항목:**
- [ ] 실제 이탈 시 `dist=` 값이 threshold(35m+α) 초과 상태로 연속 3회 출력
- [ ] `[Reroute]` 정상 트리거

---

## Phase 5: 통합 검증

### 시나리오별 로그 패턴

| 시나리오 | 기대 로그 패턴 |
|----------|--------------|
| 직진 | `✅` 연속, `seg=` 단조 증가, `Δ=` 소값 유지 |
| 우회전 | 회전 완료 후 `seg=` 전환, `Δ=` 감소, `✅` 유지 |
| 좌회전 | 동일 |
| 유턴 | 유턴 완료 후 `seg=` 전환, `Δ≈0°`, `✅` 유지 |
| 실제 이탈 | `dist=` 값이 threshold 초과 연속 → `[Reroute]` 트리거 |
| 정차 | `score = dist` (`Δ` 패널티 없음) |
| GPS 손실 | 기존 `[GPS] loss` → 매칭 스킵 동작 유지 |

### 회귀 확인

- [ ] `[Track] step=` 전진이 회전 후 정상 동작
- [ ] `[Voice]` 안내 타이밍 변화 없음
- [ ] `[State]` 불필요한 `navigating → rerouting` 전이 없음
