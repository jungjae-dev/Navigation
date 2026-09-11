# 주행화면 UI 설계 문서

> 작성일: 2026-05-22  
> 브랜치: feature/37-refactoring-navi-ui  
> 목적: 주행화면 전체 설계 현황 정리 및 개선 방향 정의

---

## 1. 화면 개요

주행화면은 경로 안내 중 운전자가 보는 핵심 화면이다.  
짧은 시간 안에 다음 행동(회전 방향, 거리)을 파악할 수 있어야 하며,  
지도·차량 위치·회전 안내·잔여 정보가 하나의 화면에서 충돌 없이 공존해야 한다.

**사용 맥락**
- 차량 주행 중 → 시선이 화면에 머무는 시간이 0.5~2초 이내
- 중요 정보는 한 눈에 파악 가능해야 함
- 터치 오류를 최소화하기 위해 버튼은 충분한 터치 영역 확보

---

## 2. 화면 구성 현황

```
┌─────────────────────────────────────────┐
│  [회전 안내 배너 - ManeuverBannerView]   │  ← safe area top
│  ─────────────────────────────────────  │
│  [다음 안내 - 소형]                      │
├─────────────────────────────────────────┤
│                                         │
│         [지도 - MKMapView]              │  ← 전체 화면
│    [재탐색 배너 - 지도 위 오버레이]      │
│                                         │
│  [속도계]          [재탐색 버튼]        │
│                    [음소거 버튼]        │
│                    [GPS 상태 아이콘]    │
│                    [재중심 버튼]        │
├─────────────────────────────────────────┤
│  [하단 바 - NavigationBottomBar]        │  ← safe area bottom
└─────────────────────────────────────────┘
```

### 컴포넌트별 현황

#### 2-1. ManeuverBannerView (회전 안내 배너)

| 항목 | 현재 값 | 설계 의도 |
|---|---|---|
| 배경 | systemBackground 95% | 지도 위에 떠 있어도 가독성 확보 |
| 아이콘 크기 | 32pt | SF Symbol 회전 방향 |
| 거리 폰트 | 36pt bold monospacedDigit | 주행 중 숫자 인식 |
| instruction 폰트 | 18pt semibold | 도로명/안내 텍스트 |
| instruction lineLimit | **1** | ← 개선 필요 |
| roadName 폰트 | 14pt medium | 방면 정보 보조 표시 |
| next maneuver | 별도 행, 소형 | 다음 회전 예고 |

#### 2-2. NavigationBottomBar (하단 정보 바)

| 항목 | 현재 값 |
|---|---|
| 배경 | systemBackground (불투명) |
| 표시 항목 | 목적지명 / 남은 거리 / 남은 시간 / 도착 시각 / 종료 버튼 |
| 수치 폰트 | 17pt medium monospacedDigit |
| 레이블 폰트 | 13pt regular |
| 종료 버튼 | 52×44pt, systemRed |

#### 2-3. SpeedometerView (속도계)

| 항목 | 현재 값 |
|---|---|
| 크기 | 70×70pt |
| 위치 | leading 16pt, bottom safe area −90pt |
| 속도 폰트 | 28pt bold monospacedDigit |
| 배경 | systemBackground, cornerRadius 12 |

#### 2-4. 플로팅 버튼 (재중심/음소거/재탐색/GPS)

| 버튼 | 크기 | 위치 |
|---|---|---|
| 재중심 | 44×44pt | trailing 16, bottom safe area −150 |
| 음소거 | 44×44pt | 재중심 위 12pt |
| GPS 상태 | 24×24pt | 음소거 위 12pt |
| 재탐색 | 44×44pt | GPS 아이콘 위 12pt |

#### 2-5. 기타 오버레이

- **재탐색 배너**: 노란 배경, 지도 위 중앙, `.rerouting` 상태에서만 노출
- **도착 팝업**: 중앙 팝업, 5초 카운트다운 후 자동 종료
- **MapMatch 디버그 오버레이**: DevTools 토글로 on/off

---

## 3. 디자인 시스템 (Theme+Navigation)

```swift
// Colors
bannerBackground    = systemBackground × 0.95
bottomBarBackground = systemBackground
maneuverIcon        = .blue
speedText           = .label
etaText             = .label
secondaryText       = .secondaryLabel
destructive         = .systemRed
gpsWarning          = .systemOrange

// Fonts
maneuverDistance    = 36pt bold monospacedDigit
maneuverInstruction = 18pt semibold
roadName            = 14pt medium
speedValue          = 28pt bold monospacedDigit
etaValue            = 17pt medium monospacedDigit
etaLabel            = 13pt regular
```

색상은 시스템 semantic color 기반이라 다크모드 자동 대응.

---

## 4. 디자인 원칙

1. **정보 위계**: 다음 회전 방향 > 거리 > 도로명 > 잔여 정보 순으로 시각적 강조
2. **색상 절제**: 강조(파랑) / 보조(회색) / 경고(빨강·주황) 3가지 이내 유지
3. **배경 불투명도**: 지도와 UI 레이어 간 충분한 대비 확보
4. **터치 영역**: 주행 중 오조작 방지를 위해 버튼 최소 44×44pt
5. **숫자 안정성**: 수치 변경 시 레이아웃 흔들림 방지 → monospacedDigit 적용
6. **다크모드**: 별도 분기 없이 semantic color로 자동 대응

---

## 5. 현재 잘 작동하는 부분 (유지)

- 전체 레이아웃 구조 (배너 상단 / 지도 전체 / 하단 바)
- CADisplayLink 기반 차량 위치 보간 및 카메라 추적
- 음성 안내 시스템 (VoiceTTSPlayer)
- 재탐색 배너 (`.rerouting` 상태 연동)
- 도착 팝업 (5초 카운트다운)
- Theme 디자인 토큰 분리 구조
- 다크모드 자동 대응
- Kakao TurnType 매핑 (type 코드 기반으로 정확)
- 7초 자동 재중심 타이머

---

## 6. 발견된 문제점

### 6-1. instruction 잘림 (높음)

**원인**: `ManeuverBannerView` instruction `.lineLimit(1)`  
**증상**: Apple Maps instruction은 교차로명 + 방면 + 도로명을 한 문장에 포함하므로 35자 이상이 일반적. 1줄 제한 시 핵심 정보(방향) 잘림

```
실제 데이터 예시:
'개화IC에서 김포, 강화 방면 김포대로(으)로 완만히 우회전'     (34자)
'마산역사거리에서 은여울중학교 방면 김포한강8로(으)로 좌회전'  (35자)
'태리교차로에서 김포한강신도시, 통진 방면 태장로(으)로 계속 이동' (33자)
```

---

### 6-2. TurnType 매핑 오류 (중간)

**원인**: `TurnType.from(appleInstructions:)` 에서 "왼쪽/오른쪽" 키워드를 leftTurn/rightTurn으로 단순 매핑  
**증상**: "차선 유지" 계열이 회전 아이콘으로 표시되어 혼란 유발

```
실제 오매핑 케이스:
'왼쪽 차선을 유지하세요'                           → leftTurn  (→ leftMerge 여야 함)
'왼쪽 차선 유지'                                  → leftTurn  (→ leftMerge 여야 함)
'개화IC에서 김포, 강화 방면 김포대로(으)로 완만히 우회전' → rightTurn (→ rightMerge 여야 함)
```

---

### 6-3. leftMerge / rightMerge 아이콘 미분화 (중간)

**원인**: `TurnType.iconName`에서 leftMerge / rightMerge 모두 `"arrow.merge"` 동일 아이콘 반환  
**증상**: 좌우 방향 구분 불가

```swift
case .leftMerge:   return "arrow.merge"   // 좌우 동일
case .rightMerge:  return "arrow.merge"   // 좌우 동일
```

---

### 6-4. Apple 경로 roadName 항상 nil (낮음)

**원인**: `MKRoute.Step`에 roadName 미제공. Apple은 instruction 안에 도로명 포함  
**증상**: 배너 하단 `[도로명] 방면` 행이 항상 미노출. instruction 1줄 제한과 조합 시 정보 손실 심각

---

### 6-5. step[0] 빈 instruction (낮음)

**원인**: Apple MKRoute 첫 step이 0m + 빈 문자열  
**증상**: 엔진이 정상 스킵하나, 극히 짧은 순간 빈 배너 노출 가능성 잠재

---

## 7. 개선 방향

### 7-1. ManeuverBannerView — instruction 표시 개선

- lineLimit: 1 → **2** (current maneuver 기준)
- 2줄일 경우 폰트 크기 자동 축소 고려 (`minimumScaleFactor`)
- next maneuver는 lineLimit 1 유지 (보조 정보이므로 압축 허용)
- instruction 폰트 크기: 18pt → **16pt** (2줄 공간 확보)
- 아이콘 크기: 32pt → **36pt** (더 직관적)

### 7-2. TurnType.from(appleInstructions:) — 매핑 규칙 보완

우선순위를 기존보다 세분화:

```
차선 유지 계열 (merge 보다 먼저 체크):
  "왼쪽 차선 유지" / "왼쪽 차선을 유지" → leftMerge
  "오른쪽 차선 유지" / "오른쪽 차선을 유지" → rightMerge

완만한 회전 (merge):
  "완만히 우회전" / "완만하게 우회전" → rightMerge
  "완만히 좌회전" / "완만하게 좌회전" → leftMerge

고속도로 진입 (merge):
  "진입" + "오른쪽" → rightMerge
  "진입" + "왼쪽" → leftMerge
  "진입" (방향 불명) → rightMerge (현행 유지)
```

### 7-3. TurnType.iconName — leftMerge / rightMerge 분화

```swift
case .leftMerge:  return "arrow.merge"             // 현행 유지 (SF Symbol 미제공)
case .rightMerge: return "arrow.merge"             // → 미러 transform으로 우측 표현
```

SF Symbol에 leftMerge 전용 심볼이 없으므로:  
뷰 레이어에서 `.rightMerge` 일 경우 이미지에 `.scaleEffect(x: -1)` 적용하여 방향 분화

### 7-4. step[0] 방어

`NavigationEngine` 또는 `RouteTracker`에서 currentManeuver 생성 시  
instruction이 빈 문자열인 step은 current로 올리지 않고 다음 step으로 즉시 전진

### 7-5. 전체 색상·시각 톤 검토

현재 Theme 구조는 적절. 추가 변경 없이 아래만 확인:
- 배너 배경 opacity 0.95 → 지도와 충분한 대비인지 실기기에서 확인
- 속도계 shadow가 배너 shadow와 시각적으로 충돌하지 않는지 확인

---

## 8. 수정 범위

| 파일 | 변경 내용 |
|---|---|
| `ManeuverBannerView.swift` | instruction lineLimit, 폰트 크기, 아이콘 크기, rightMerge 미러 |
| `TurnType.swift` | `from(appleInstructions:)` 차선유지·완만한회전 매핑 추가 |
| `NavigationEngine` 또는 `RouteTracker` | step[0] empty instruction 방어 (확인 후 결정) |

### 수정하지 않는 것
- Theme+Navigation (토큰 구조 유지)
- NavigationBottomBar (현행 레이아웃 적절)
- SpeedometerView (현행 유지)
- 플로팅 버튼 위치/크기
- 음성·재탐색·도착 팝업 로직

---

## 9. 완료 기준

1. 35자 이상 instruction이 2줄 이내로 잘림 없이 표시됨
2. "왼쪽/오른쪽 차선 유지" 안내에 merge 계열 아이콘이 표시됨
3. leftMerge / rightMerge 아이콘이 방향에 따라 시각적으로 구분됨
4. 주행 시작 직후 빈 배너 노출 없음
5. 다크모드에서 배너 가독성 유지
