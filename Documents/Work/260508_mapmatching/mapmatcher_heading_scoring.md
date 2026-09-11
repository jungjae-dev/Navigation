# MapMatcher 세그먼트 선택 개선: 거리 + Heading 복합 스코어

## 문제 요약

경로를 정상 주행 중 **회전(우회전/좌회전/유턴)** 구간에서 맵매칭이 실패하여
차량 아이콘이 회색으로 바뀌고 경로 이탈로 재탐색이 트리거된다.

---

## 시나리오 1: 우회전 (실제 발생 로그 기반)

### 상황
```
seg=a (진입로, 307°) ──────── [P] ──────── [B: 교차점]
                               ↑
                          수선의 발
                         (11.6m)
                               |
                          차량 GPS
                          heading=60°
                              ──────→  seg=a+1 (새 도로, 63°)
```

| t(s) | GPS heading | 최선 세그먼트 | dist | Δ | 결과 |
|------|------------|-------------|------|---|------|
| 233~235 | 311° | seg=a | 3~5m | 4° | ✅ |
| 236~238 | 337°→3°→27° | seg=a | 4~9m | 29°~80° | ✅ (Δ < 90°) |
| **239** | **60°** | **seg=a** | **11.6m** | **112°** | **❌** |
| 240 | 63° | seg=a | 15.7m | 116° | ❌ |
| 241 | 63° | seg=a | 20.5m | 116° | ❌ → 재탐색 |

### 현재 코드에서 왜 seg=a+1을 못 찾는가

차량이 **폴리라인 꼭짓점 B(교차점)보다 먼저 물리적으로 회전**한다.

```
seg=a: ─── P(수선의 발) ──── B(교차점)
              ↑ 11.6m               ↑ B까지 거리 > 11.6m
           (차량 위치)
```

- `projectPointOnSegment` 결과:
  - seg=a까지 거리 = **11.6m** (P에 수직 투영)
  - seg=a+1까지 거리 = **B까지 유클리드 거리** > 11.6m (B가 아직 앞에 있음)
- seg=a가 거리상 더 가까워서 선택됨
- 이후 heading 검증: Δ=112° > 90° → ❌ 실패

### 핵심: seg=a+1의 heading은 완벽히 일치
| 세그먼트 | 거리 | Δ |
|----------|------|---|
| seg=a (구 도로) | 11.6m | 112° |
| seg=a+1 (새 도로) | ~15m | **3°** |

거리만으로 선택하면 seg=a 선택 → heading 실패.  
**heading을 포함한 스코어로 선택하면 seg=a+1 선택 → 매칭 성공.**

---

## 시나리오 2: 유턴

### 상황

```
  ──────────────── seg=b (90°, 동쪽) ──────→ ↺
  ←──────────────── seg=b+N (270°, 서쪽) ────
                                          차량
                                         heading
                                          270°
```

차량이 유턴 완료 후 heading ≈ 270°.

| 세그먼트 | 거리 | Δ | 기존 결과 |
|----------|------|---|----------|
| seg=b (진입로, 90°) | 8m | **180°** | ❌ Δ > 90° 컷오프 |
| seg=b+N (역방향, 270°) | 12m | **0°** | ❌ 거리 기준 탈락 후 컷오프 |

```
현재: 양쪽 모두 Δ > 90° → 둘 다 ❌ → 재탐색

개선: score 비교
  seg=b   dist=8m  Δ=180° → score = 8 + (180/180)×30 = 38.0
  seg=b+N dist=12m Δ=0°   → score = 12 + 0           = 12.0 ✅
```

---

## 시나리오 3: 직진 (정상 케이스 — 유지되어야 함)

```
seg=c (직진, 45°) ─────────────→
차량 heading = 47°
```

| 세그먼트 | 거리 | Δ |
|----------|------|---|
| seg=c (현재 도로) | 3m | 2° |
| 병렬 도로 | 25m | 5° |

→ 거리가 월등히 가까운 seg=c 선택. heading 패널티 차이 미미. 정상 동작 유지.

---

## 근본 원인

현재 `MapMatcher.match()` 처리 순서:

```
1. 최소 거리 기준으로 세그먼트 선택  ← heading 미고려
2. 거리 threshold 검증
3. heading 검증 (maxAngleDelta=90° 고정 컷오프)  ← 탈락
```

**두 가지 문제:**
1. **세그먼트 선택 단계**에서 heading을 무시 → 회전 후 잘못된 세그먼트 선택
2. **검증 단계**에서 고정 90° 컷오프 → 유턴(180°) 처리 불가

---

## 해결 방안: 거리 + Heading 복합 스코어

### 수식 정의

#### 1. 수선의 발 투영 거리 (Perpendicular Projection Distance)

GPS 좌표 P를 세그먼트 AB 위에 투영한 점 Q까지의 거리.

```
         P (GPS 좌표)
        /|
       / |  ← distance = |PQ|
      /  |
     /   |
A───Q────+────────────── B
    ↑
 투영점 Q

t = clamp( (AP · AB) / |AB|² , 0, 1 )
Q = A + t × AB
distance = |PQ|
```

t 값에 따른 투영 위치:

```
 t < 0          0 ≤ t ≤ 1          t > 1
 Q = A (clamp)   Q = 수직 투영점   Q = B (clamp)
   │                                     │
   P                                     P
   │\                                   /│
   │ \                                 / │
   │  Q=A ──────────────────────── B=Q  │
(A 이전)      세그먼트 내부         (B 이후)
```

#### 2. 세그먼트 방위각 (Bearing)

두 좌표 A → B 방향의 방위각 (0°=북, 90°=동, 시계방향).

```
        0° (N)
         ↑
         │
270° ────┼──── 90° (E)
(W)      │
         ↓
        180° (S)
```

```
Δlat = B.lat - A.lat
Δlon = B.lon - A.lon

bearing = atan2(Δlon × cos(A.lat), Δlat) × (180 / π)
bearing = (bearing + 360) mod 360
```

방위각 예시:
```
  A ──────→ B   bearing = 90°  (동쪽)

  A
   ↘          bearing = 135° (남동)
    B

      B
     ↗          bearing = 307° (북서, 로그 속 진입로 방향)
  A
```

#### 3. 각도 차이 (Heading Delta)

GPS course와 세그먼트 bearing 사이의 최소 각도 차이 (0°~180°).

```
delta = |course - bearing|
headingDelta = min(delta, 360° - delta)
```

wrap-around 예시 (로그 속 우회전 케이스):
```
  GPS course  = 60°
  Seg bearing = 307°

  delta  = |60 - 307| = 247°  ← 긴 쪽
  360 - 247 = 113°             ← 짧은 쪽

  headingDelta = min(247°, 113°) = 113°

         0° (N)
          │
    307°  │  60°
       ╲  │  ╱
        ╲ │ ╱
    113° ╲│╱
  ────────┼──────── 90° (E)
          │
         180°
```

- 범위: 0° (완전 일치) ~ 180° (정반대)
- `headingDelta = 0°`: 차량이 세그먼트 방향과 동일하게 진행
- `headingDelta = 180°`: 차량이 세그먼트 반대 방향 진행 (역주행)

#### 4. 매칭 거리 임계값 (Distance Threshold)

```
threshold = thresholdBase + speed × thresholdTimeFactor
           = 35(m)      + speed(m/s) × 1.0(s)
```

```
  정차(0km/h):   threshold = 35m
  │←────── 35m ──────→│

  30km/h(8.3m/s): threshold = 43.3m
  │←──────────── 43.3m ────────────→│

  60km/h(16.7m/s): threshold = 51.7m
  │←───────────────────── 51.7m ──────────────────────→│
```

속도가 빠를수록 threshold가 커짐. GPS 위치가 실제보다 1초 뒤처질 경우의 이동거리를 보정.

#### 5. 세그먼트 스코어 (Score)

```
score = distance + (headingDelta / 180°) × headingWeight
           ↑                  ↑                  ↑
      실제 투영 거리      방향 불일치 비율      30m (고정)
      (0m ~ threshold)    (0.0 ~ 1.0)
```

| 변수 | 설명 | 값 |
|------|------|-----|
| `distance` | 수선의 발 투영 거리 (m) | 실측값 |
| `headingDelta` | GPS course ↔ 세그먼트 bearing 최소 각도 차이 (°) | 0°~180° |
| `headingWeight` | heading 180° 불일치에 해당하는 가상 거리 (m) | **30m** |

score 구성 시각화 (우회전 케이스):
```
seg=a   dist=11.6m  Δ=112°  score=30.3
  [══ 11.6m 거리 ══][══════ 18.7m heading 패널티 ══════]  = 30.3

seg=a+1 dist=14.8m  Δ=3°    score=15.3  ✅
  [════════ 14.8m 거리 ════════][0.5]  = 15.3
```

`headingDelta=0°` → 패널티 0, score = distance만  
`headingDelta=180°` → 패널티 최대(30m), 30m 더 멀리 있는 것과 동등  

**headingWeight=0 적용 조건** (heading score 비활성, 거리만 사용):
- 도보 모드 (`transportMode == .walking`)
- 저속 (`speed < 1.4 m/s` = 5 km/h): GPS course 부정확
- GPS course 미확보 (`course < 0`): 터널, 첫 fix 전

#### 6. 탐색 종료 조건

```
threshold 초과 연속 횟수 > N (N = 3)
```

직진 vs 회전 구간에서의 탐색 거리 패턴:

```
[직진] 거리가 단조 증가 → N=1 만에 종료
  seg=k   : 3m  ✓
  seg=k+1 : 7m  ✓
  seg=k+2 : 40m ✗ (1회)
  seg=k+3 : 55m ✗ (2회)
  seg=k+4 : 68m ✗ (3회) → break

[우회전] 교차점 꼭짓점에서 거리가 일시 증가 후 감소
  seg=a   : 11.6m ✓  ← 진입로
  seg=a+1 : 38m   ✗ (1회) ← 꼭짓점 부근
  seg=a+2 : 42m   ✗ (2회)
  seg=a+3 : 14.8m ✓  ← 새 도로 (score 우세, 선택) → counter 리셋
```

N=3 으로 회전 구간의 꼭짓점 세그먼트를 건너뛰고 새 도로까지 탐색 가능.

### 시나리오별 스코어 비교

**우회전:**
| 세그먼트 | 거리 | Δ | 스코어 |
|----------|------|---|--------|
| seg=a (구 도로) | 11.6m | 112° | 11.6 + (112/180)×30 = **30.3** |
| seg=a+1 (새 도로) | ~15m | 3° | 15 + (3/180)×30 = **15.5** ✅ |

**유턴:**
| 세그먼트 | 거리 | Δ | 스코어 |
|----------|------|---|--------|
| seg=b (진입로) | 8m | 180° | 8 + 30 = **38** |
| seg=b+N (역방향) | 12m | 0° | 12 + 0 = **12** ✅ |

**직진 (정상):**
| 세그먼트 | 거리 | Δ | 스코어 |
|----------|------|---|--------|
| seg=c (현재 도로) | 3m | 2° | 3 + 0.3 = **3.3** ✅ |
| 병렬 도로 | 25m | 5° | 25 + 0.8 = **25.8** |

모든 시나리오에서 올바른 세그먼트가 선택됨.

---

## 탐색 방향 설계

### 결론: Forward only, Backward 제거

| 시점 | 탐색 시작점 |
|------|------------|
| 주행 시작 | `seg=0` |
| 이후 주행 중 | `currentSegmentIndex` (forward only) |

**Backward search 제거 이유:**
- 차량은 경로를 앞으로만 진행
- 뒤쪽 세그먼트는 차량 진행 방향의 반대를 가리키므로 `headingDelta`가 크고 → score가 높아져 → 자연히 선택되지 않음
- Backward search를 넣어도 heading score로 인해 선택되지 않으므로 불필요

```
뒤쪽 seg: distance=4m, Δ=160° → score = 4 + (160/180)×30 = 30.7
앞쪽 seg: distance=6m, Δ=5°  → score = 6 + (5/180)×30  = 6.8  ✅
```

---

## 개선 알고리즘

```
1. seg=currentSegmentIndex 부터 forward 탐색
2. 각 세그먼트: score = distance + (Δ / 180°) × headingWeight
3. threshold 거리 초과 연속 N회 → break
4. 최소 score 세그먼트 선택
5. 선택 세그먼트의 distance > threshold → 매칭 실패 (isMatched = false)
6. 매칭 성공 → currentSegmentIndex 갱신
```

---

## 코드 변경 범위

**`MapMatcher.swift`**

| 항목 | 현재 | 변경 후 |
|------|------|---------|
| 탐색 방향 | forward + backward | **forward only** |
| 탐색 시작점 | `currentSegmentIndex` | 주행 시작: `0`, 이후: `currentSegmentIndex` |
| 탐색 종료 조건 | `distance > prevDist` (즉시 break) | threshold 초과 연속 N회 시 break |
| 세그먼트 선택 기준 | 최소 거리 | **최소 score (거리 + heading 패널티)** |
| heading 검증 | `maxAngleDelta = 90°` 하드컷 | **제거** (스코어에 통합) |
| 매칭 실패 조건 | 거리 초과 OR heading 초과 | **거리 threshold 초과만** |

**`headingWeight` 파라미터**
- 기준값 **30m** (180° 불일치 시 가상 거리 30m 추가)
- 크게 할수록 heading 정렬 강화, 작게 할수록 거리 우선
- 저속(< 5km/h) 또는 course 미확보 시 → `headingWeight = 0` (거리만 사용)

---

## 미해결 엣지케이스

- **GPS heading 부정확 구간**: 고가 하부, 터널 입출구 등에서 course가 실제 방향과 다를 수 있음. heading score가 오히려 잘못된 세그먼트를 선호할 수 있음.
  - 완화: `accuracy > threshold` 시 `headingWeight = 0` 처리 (기존 GPS 품질 가드 활용)
- **병렬 도로 구분**: heading이 동일한 평행 도로 두 개가 모두 threshold 내에 있을 경우 거리로만 판별. 현재와 동일하므로 회귀 없음.
