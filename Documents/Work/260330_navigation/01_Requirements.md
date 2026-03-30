# 네비게이션 주행 엔진 요구사항

> 작성일: 2026-03-30
> 목적: 기존 주행 관련 코드를 삭제하고, 새 NavigationEngine을 설계/개발하기 위한 요구사항 정의

---

## 1. 개요

### 1.1 배경
- 기존 주행 코드는 프로토타입 수준으로, 치명적 버그(보간기 미동작, 주차 모드 크래시 등)와 구조적 문제(하드코딩, 책임 과다)가 있음
- TMAP 분석을 참고하여 GPS → 맵매칭 → 안내 계산 → UI 갱신 파이프라인을 새로 구축

### 1.2 범위
- **삭제 대상**: Feature/Navigation/*, Service/Guidance/*, Service/Voice/*, Service/Interpolation/*, Service/TurnPointPopup/*, Service/Parking/*, Map/MapCamera.swift, Map/Vehicle3DOverlayView.swift
- **유지 대상**: NavigationSessionManager (인터페이스 수정), CarPlay 코드 (새 엔진 연결), Route/RouteStep 모델 (확장), LocationService
- **지도**: Apple MKMapView 사용 (자체 렌더링 엔진 없음)

### 1.3 지원 모드
- 자동차: 카카오 우선, Apple 폴백
- 도보: Apple (카카오 미지원 → 자동 폴백)
- 자전거: 미지원 (추후 검토)

---

## 2. 입력 데이터

### 2.1 경로 데이터 모델 (Route / RouteStep)
- 카카오 API + Apple MapKit 데이터의 **합집합**으로 모델 구성
- 있는 데이터는 모두 저장하여 표시에 활용

#### RouteStep 확장 필드
| 필드 | 카카오 | Apple | 용도 |
|------|--------|-------|------|
| instructions (String) | guide.guidance | step.instructions | 안내 텍스트 |
| distance (Double) | guide.distance | step.distance | 다음 안내까지 거리 |
| duration (TimeInterval?) | guide.duration | - | 구간 예상 시간 |
| polylineCoordinates ([CLLocationCoordinate2D]) | 폴리라인 분할 | step.polyline | 구간별 좌표 배열 |
| turnType (Int?) | guide.type | - | 회전 유형 코드 |
| roadName (String?) | guide.name | - | 도로명 |

### 2.2 카카오 스텝 폴리라인 분할
- 현재 카카오 변환 시 guide 좌표(점 1개)만 저장 → **전체 폴리라인을 guide 좌표 기준으로 분할**
- 순방향 탐색: searchStartIndex를 유지하며 guide 좌표에 가장 가까운 폴리라인 점을 찾아 분할
- U턴/겹침 경로도 순방향 탐색으로 처리

### 2.3 GPS 데이터
- **1초 틱 보장**: GPS 수신 여부와 관계없이 엔진에 1초마다 데이터 전달
  - 수신 시: GPSData(coordinate, heading, speed, accuracy, timestamp, isValid: true)
  - 미수신 시: GPSData(lastCoordinate, lastHeading, lastSpeed, accuracy, timestamp, isValid: false)
- 엔진은 항상 1초마다 동작, valid/invalid로 분기 처리
- `desiredAccuracy = kCLLocationAccuracyBestForNavigation`

### 2.4 Location Type
- **real**: 실제 GPS (CoreLocation)
- **simul**: 가상 주행 (경로 위 시뮬레이션)
- **file**: GPX 파일 재생
- 3가지 타입 모두 동일한 GPSData를 엔진에 전달 → 엔진은 소스를 알 필요 없음

---

## 3. 엔진 파이프라인

### 3.1 기본 동작 (GPS 업데이트 1회당)

```
GPSProvider (1초 보장)
    │ GPSData (valid/invalid)
    ▼
MapMatcher (폴리라인 스냅)
    │ MatchedPosition (매칭 좌표, 세그먼트 인덱스, 매칭 성공 여부)
    ▼
RouteTracker (경로 진행 추적)
    │ current/next step, 남은 거리/시간/ETA
    ▼
NavigationGuide (단일 구조체 발행)
    │
    ├→ iPhone UI (ManeuverBanner, BottomBar, 속도계 등)
    ├→ CarPlay UI (CPManeuver, CPRouteInformation)
    └→ VoiceEngine (음성 안내 트리거)
```

### 3.2 렌더링 구조 (Apple MKMapView)
- **아바타**: MKPointAnnotation으로 표시
- **부드러운 이동**: CADisplayLink 60fps로 GPS 간 보간
  - C→D 구간을 60프레임으로 선형 보간
  - annotation.coordinate + mapView.camera를 같은 프레임에서 동시 갱신 (떨림 방지)
- **경로 표시**: MKOverlay (정적, 주행 시작 시 1회 추가, 재탐색 시 교체)
- **카메라 이동**: 매 프레임 MKMapCamera 적용 (지도가 차량 아래로 흘러감)
- 약 1초 지연 존재 (맵매칭 스냅으로 체감 최소화)

---

## 4. 맵매칭 (Polyline Snap)

### 4.1 알고리즘
- GPS 좌표를 경로 폴리라인 위에 투영 (가장 가까운 점/세그먼트)
- 탐색 범위: 현재 세그먼트 기준 ±N 윈도우 (전체 스캔 방지)

### 4.2 판정 기준
- **거리 임계값**: 50m 고정 (추후 속도 기반으로 개선)
- **방향 검증**: GPS heading vs 폴리라인 세그먼트 방향 각도차 < 90° (역주행/오매칭 방지)
- 거리 + 방향 모두 만족 → 매칭 성공

### 4.3 매칭 결과
- 매칭 성공: 폴리라인 위 투영 좌표 반환 (도로 위에 스냅)
- 매칭 실패: 이탈 카운터 증가

---

## 5. 경로 진행 추적

### 5.1 스텝 전진 판정
- 현재 안내 포인트까지 남은 거리 ≤ 30m → 다음 스텝으로 전진
- TMAP 방식 동일

### 5.2 동시 추적
- **current step**: 현재 회전 안내 (아이콘 + 거리 + 안내문)
- **next step**: 다음 회전 안내 (간략 표시)
- TMAP의 dual-point 방식 적용

### 5.3 진행 정보 계산
- 현재 안내까지 남은 거리
- 목적지까지 남은 거리 / 시간 / ETA

---

## 6. 경로 상태 머신

```
preparing ──→ navigating ──→ arrived (30m 이내)
                  │
                  ├──→ rerouting ──→ navigating (복귀)
                  │
                  └──→ stopped (사용자 종료)
```

- **preparing**: 엔진 초기화, 첫 GPS 대기
- **navigating**: 정상 주행 중
- **rerouting**: 재탐색 진행 중
- **arrived**: 목적지 30m 이내 도달
- **stopped**: 사용자가 안내 종료

### 6.1 제외 항목
- PASSGOAL (목적지 통과): 없음 — 30m 도착 판정으로 충분
- parkingApproach: Phase 2
- GPS 불량 별도 상태: 없음 — 지도에 GPS 아이콘으로 표시

---

## 7. 이탈 감지 + 재탐색

### 7.1 이탈 판정
- 맵매칭 실패 (거리 > 50m 또는 각도차 > 90°) **연속 3회** → 이탈 확정
- **보호 조건**:
  - 출발 후 35m / 5초 이내: 판정 보류
  - GPS 정확도 > 120m: 판정 보류

### 7.2 재탐색 종류 (Phase 1)
- **이탈 자동 재탐색**: 이탈 확정 시 현재 위치 → 원래 목적지로 경로 재요청
- **사용자 수동 재탐색**: 버튼으로 수동 트리거

### 7.3 Phase 2
- 주기적 재탐색 (5분, 실시간 교통 반영)

---

## 8. 음성 안내

### 8.1 트리거 거리
**일반도로:**
| 거리 | 안내 내용 |
|------|----------|
| 1200m | 사전 도로명 안내 ("{도로명} 방면 {방향}") |
| 300m | 사전 거리 안내 ("300미터 앞 {방향}") |
| 120m | 직전 안내 ("전방 {방향}") |

**고속도로 (속도 > 80km/h):**
| 거리 | 안내 내용 |
|------|----------|
| 1200m | 사전 도로명 안내 |
| 500m | 사전 거리 안내 |
| 200m | 직전 안내 |

### 8.2 텍스트 생성 (프로바이더별 분기)
- **엔진은 공통**: 거리 트리거 판정만 담당
- **텍스트 생성은 프로바이더별**:

**카카오:**
- type 코드 + name으로 자유롭게 조합
- 1200m: "{guide.name} 방면 {type→방향}입니다"
- 300m: "300미터 앞 {type→방향}"
- 120m: "전방 {type→방향}"

**Apple:**
- instructions 텍스트 그대로 활용
- 1200m: "{instructions}"
- 300m: "300미터 앞, {instructions}"
- 120m: "전방, {instructions}"

### 8.3 음성 재생 정책
- **겹침 처리**: 큐 방식 — 현재 안내 끝난 후 다음 안내 재생
- **TTS**: AVSpeechSynthesizer (한국어)
- **언어**: 한국어만 우선 지원
- **오디오 세션**: duckOthers (배경 음악 음량 낮춤)

---

## 9. 터널 / GPS 손실

### 9.1 Dead Reckoning
- GPS invalid 연속 시 추정 이동
- **추정 방식**: 마지막 속도 × 경과시간으로 이동 거리 계산 → 경로 폴리라인을 따라 이동
- 맵매칭된 위치를 기준으로 폴리라인 위에서 전진
- CADisplayLink 보간과 연계하여 부드러운 이동 유지

### 9.2 GPS 복귀 시
- 새 GPS 위치로 맵매칭 재개
- 급점프 방지를 위한 전환 처리 필요

---

## 10. 카메라

### 10.1 속도별 고도 (TMAP 값)
**자동차:**
| 속도 | 고도 |
|------|------|
| 정지~저속 | 500m |
| 시내 60km/h | 1000m |
| 고속 100km/h | 2000m |

**도보:**
| 속도 | 고도 |
|------|------|
| 정지 | 200m |
| 보행 | 300m |

### 10.2 기타 카메라 설정
- **피치**: 자동차 45°, 도보 30°
- **heading**: 진행 방향으로 회전

### 10.3 사용자 지도 조작
- 사용자 pan/zoom 시: 자동 추적 해제
- **복귀 방식**: 7초 미조작 자동 복귀 + 리센터 버튼 (둘 다)

---

## 11. 주행 화면 UI (Phase 1)

### 11.1 구성 요소

```
┌─────────────────────────────────────────┐
│ ┌─────────────────────────────────────┐ │
│ │  🔄 300m 우회전                      │ │ ← ManeuverBanner
│ │     ↳ 이후 1.2km 좌회전              │ │ ← next 안내
│ ├─────────────────────────────────────┤ │
│ │                                     │ │
│ │           🗺️ 지도                    │ │
│ │              🚗                     │ │
│ │                                     │ │
│ │  ┌────────┐                         │ │
│ │  │ 58km/h │                         │ │ ← 속도계
│ │  └────────┘              [📍]       │ │ ← 리센터 버튼
│ │                    [📡]             │ │ ← GPS 상태 아이콘
│ ├─────────────────────────────────────┤ │
│ │  강남역 │ 12.5km │ 18분 │ 14:32도착 │ │ ← BottomBar
│ │                        [안내 종료]   │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 11.2 포함 항목
- **ManeuverBanner**: current + next 회전 안내 (아이콘 + 거리 + 안내문)
- **BottomBar**: ETA, 남은 거리, 남은 시간, 안내 종료 버튼
- **속도계**: 현재 GPS 속도 표시
- **리센터 버튼**: 자동 추적 해제 시 표시
- **GPS 상태 아이콘**: GPS invalid 시 표시
- **재탐색 표시**: "경로를 재탐색 중입니다" 배너
- **음성 음소거 토글**: 음성 안내 켜기/끄기
- **경로 폴리라인**: 전체 경로를 동일 색상으로 지도에 표시
- **출발지/목적지 마커**: 지도에 출발지, 도착지 핀 표시
- **도착 팝업**: "목적지에 도착했습니다" + 주행 종료 버튼 + 5초 타이머 자동 종료
- **경로 전체 보기**: 주행 중 줌아웃하여 남은 경로 전체를 볼 수 있는 기능
- **다크모드**: 시스템 다크모드 연동

### 11.3 Phase 1 제외
- 차선 안내 (데이터 없음)
- SDI 과속카메라 (데이터 없음)
- Progress Bar
- 고속도로 모드 UI
- 햅틱 피드백

---

## 12. CarPlay 연동

### 12.1 방침
- 기존 CarPlay 코드 유지, 새 엔진에 맞게 연결 수정
- Phase 1에서 iPhone과 같이 처리

### 12.2 구조
- NavigationSessionManager가 NavigationEngine 소유
- **iPhone**: NavigationGuide → 주행 화면 UI
- **CarPlay**: NavigationGuide → CarPlayNavigationHandler → CPManeuver / CPRouteInformation
- 양방향 동기화 유지 (iPhone 시작 ↔ CarPlay 시작)

---

## 13. 시스템 / 앱 상태

### 13.1 화면 꺼짐 방지
- 앱 시작 시 `isIdleTimerDisabled = true` 항상 처리

### 13.2 백그라운드 처리
- **주행 중**: Background Location + Audio 유지 (GPS 수신 + 음성 안내 계속)
- **비주행 시**: LocationService stop 처리

### 13.3 테스트 모드
- Location Type 3종: real / simul / file
- 동일한 GPSData 인터페이스로 엔진에 전달
- 엔진은 소스를 알 필요 없음

---

## 14. 설계 원칙

### 14.1 엔진 분리
- **엔진은 순수 로직**: UIKit, MapKit, SwiftUI import 없음
- CoreLocation 좌표 타입(CLLocationCoordinate2D, CLLocationDistance 등)만 사용
- 입력: GPSData → 출력: NavigationGuide (구조체)
- UI는 NavigationGuide를 Combine 구독하여 표시

### 14.2 UI 프레임워크
- UIViewController + SwiftUI (Hosting)
- 주행 화면 뷰 컴포넌트는 SwiftUI로 구현

### 14.3 스레딩
- 엔진 계산: Background 스레드
- UI 갱신: MainActor로 전달
- Combine `.receive(on: DispatchQueue.main)` 활용

### 14.4 반응형 패턴
- Combine `CurrentValueSubject<NavigationGuide, Never>` — 현재 앱 패턴 유지
- iPhone UI + CarPlay가 동시 구독

### 14.5 전환 방식
- 기존 주행 코드 한번에 삭제 → 새 코드로 교체

### 14.6 테스트
- 엔진 핵심 로직에 Swift Testing 단위 테스트
  - MapMatcher, RouteTracker, OffRouteDetector, VoiceEngine 트리거, DeadReckoning
- UI는 가상 주행 모드(simul/file)로 수동 검증

---

## 15. Phase 구분

### Phase 1 (핵심 주행 MVP)
1. 엔진 파이프라인 (GPS → 맵매칭 → 안내 계산 → NavigationGuide 발행)
2. 맵매칭 (50m 고정, 방향 검증)
3. 경로 진행 추적 (30m 전진, current+next)
4. 상태 머신 (preparing → navigating → arrived/stopped/rerouting)
5. 이탈 감지 + 재탐색 (자동 + 수동)
6. 음성 안내 (거리 트리거, 프로바이더별 텍스트, 큐 방식, 음소거 토글)
7. 터널 Dead Reckoning
8. 차량 보간 (CADisplayLink 60fps)
9. 카메라 (TMAP 속도별 고도, 7초 자동복귀 + 리센터)
10. 주행 화면 UI (배너, 바텀바, 속도계, 리센터, GPS 상태, 재탐색 표시)
11. 경로/마커 표시 (폴리라인 동일 색상, 출발지/목적지 마커)
12. 도착 처리 (도착 팝업 + 5초 자동 종료)
13. 경로 전체 보기 (줌아웃)
14. 다크모드 (시스템 연동)
15. CarPlay 연동 (새 엔진에 맞게 수정)
16. 백그라운드 GPS + 음성
17. 테스트 모드 (real / simul / file)
18. Route 모델 확장 + 카카오 스텝 폴리라인 분할

### Phase 2 (안정성 + 사용성)
- parkingApproach (주차 모드)
- 주기적 재탐색 (5분)
- 맵매칭 임계값 속도 기반 개선
- Progress Bar
- 도착 화면 (POI + 주차장)
- 고속도로 모드 UI
- 회전 지점 안내 맵 (모든 회전 지점 300m 전 표시, ManeuverBanner 아래 오버레이, 카메라를 회전 지점에 고정 + heading 방향 회전, 차량 annotation이 실제 이동, 통과 후 자동 닫힘)
- 경유지 (다중 목적지) 지원

### Phase 3 (부가 기능)
- Live Activity (잠금화면 / Dynamic Island)
- SDI 과속카메라 (공공데이터)
- 대안 경로 표시 + 경로변경 알림
- 주행 통계
- 반대편 도착 처리
- 다국어 지원
