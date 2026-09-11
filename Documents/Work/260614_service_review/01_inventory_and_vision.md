# 서비스 출시 검토 — 1단계 인벤토리 & 확장 비전

작성일: 2026-06-14
목적: 흩어진 기능들을 정리하고, 어떤 서비스로 출시할지 결정하기 위한 근거 수집
타깃 시장: 한국

---

## A. 현재 기능 인벤토리 (코드 기준)

내비게이션 핵심 파이프라인(GPS → 맵매칭 → 길안내)은 이미 완성도 높음. 부가/특화 기능이 반쪽 상태.

### ✅ 완성 (Done)
| 기능 | 설명 | 핵심 의존성 |
|---|---|---|
| Location Service | 실 GPS·파일재생·시뮬 통합 위치 제공 | CoreLocation |
| Map Matching | GPS를 경로 폴리라인에 스냅 (course 기반) | 경로 폴리라인 |
| Navigation Engine | 라우팅·추적·길안내·상태관리 | MapMatcher |
| Route Service (LBS) | Kakao(주) + Apple(폴백) 경로 추상화 | Kakao API, MapKit |
| Voice Guidance | 한국어 TTS 턴 안내 | AVSpeechSynthesizer |
| Rerouting | 이탈 시 자동/수동 재탐색 (3회 제한) | OffRouteDetector |
| Turn-by-Turn UI | ManeuverBanner·BottomBar·속도계 | NavigationEngine |
| Search | 장소 검색 + 최근/즐겨찾기 | MapKit |
| Route Preview | 다중경로 선택·옵션·ETA 비교 | Route service |
| 따릉이 (Bike Sharing) | 서울 공공자전거 마커·대여·도보안내 | 서울 Open API |
| Recording | 주행 NDJSON 기록/재생 | Documents/ |
| Virtual Drive | 사전 매칭 경로 시뮬 (테스트용) | LocationSimulator |

### 🟡 반쪽 (Partial / Experimental)
| 기능 | 상태 |
|---|---|
| 버스 | 마커·실시간도착 일부; 상세·노선·시간표 UI 미완 (Phase 2~4 미착수) |
| 지하철 | 마커만; 상세·노선·시간표 미완 (Phase 5~7 미착수) |
| CarPlay | 구 엔진 연결, 신 엔진 재통합 필요 |
| 차량 아이콘 3D | 디자인만; USDZ·SceneKit 코드 없음 |
| 차량 아이콘(내비 화면) | 하드코딩, 설정 연동 안 됨 |
| 설정 | 기본 골격 |
| UI 디자인 통일 | 진행 중 (spec 002-ui-design-refresh) |
| DevTools | GPS 오버라이드·디버그 |

### ❌ 공백 (없음, 출시형 내비가 보통 갖춤)
오프라인 지도, 계정/클라우드 동기화, 차로 안내, 과속카메라, 주차 연동, 다국어, 즐겨찾는 경로, Live Activity/Dynamic Island

### 기술 스택
- 지도: Apple MapKit(주) + Kakao(경로/검색)
- UI: UIKit 프로그래매틱 + 일부 SwiftUI, MVVM + Coordinator + Combine
- 저장: SwiftData(즐겨찾기·검색기록·기록 분리), UserDefaults, 디스크 캐시
- API: Kakao REST, 서울 Open API(버스·지하철·따릉이), Firebase Remote Config
- 동시성: Swift 6 strict, MainActor 기본 격리

---

## B. 확장 비전 (인터뷰 기준)

### 핵심 불만 (왜 만들었나)
- **기존 지도 앱이 너무 복잡·무겁다** → 가볍고 깔끔한 UI를 원함

### 확장하고 싶은 기능
- 도보 내비게이션
- **도보 AR 내비게이션**
- **지하주차장 AR 내비게이션**
- 서울시 공공데이터 심화 활용
- 자전거 / 마이크로모빌리티 강화

### 한계 인식
- "차량 내비는 제공되는 API만 써서 개발 여지가 적다" → 차량 영역은 차별화 어려움

### 수익 모델
- 무료 + 광고 / 제휴

### 차별화 지점 (대기업이 잘 안 하는 곳)
- **틈새 사용자 경험** (가볍고 깔끔)
- **특정 이동수단 전문성**

---

## C. 포지셔닝 가설 (시장조사로 검증 대상)

> "네이버·카카오·티맵이 무거운 만능 차량 앱이라면, 이 앱은 **자전거·도보·대중교통에 특화된 가볍고 깔끔한 앱** — 거기에 **AR(도보/지하주차장)** 이라는 대기업이 안 하는 차별화 기능을 얹는다."

### 맞물리는 두 통찰
1. **차량 내비는 버리거나 보조로** — API 의존이라 차별화 불가, 거대 앱과 정면 승부 불리
2. **AR + 서울 공공데이터 + 가벼운 UX = 해자** — 대기업이 안 하거나 못 하는 영역

### 시장조사로 확인할 질문
1. 도보 AR / 실내(지하주차장) AR 내비 — 한국에 이미 있나? 어디까지?
2. AR 내비 기술 현실성 (ARKit + VPS, 실내 측위) 과 글로벌 선례
3. 이동수단 특화 앱 선례의 시장성·수익화 (자전거·대중교통)
4. 무료+광고 모델 현실성 (지도/내비 광고 수익, 사용자 임계점)
5. 서울시 공공데이터로 실내지도·주차장·교통 AR 토대가 가능한가

---

## 다음 단계
→ `02_market_research.md` : 위 5개 질문에 대한 출처 기반 시장 조사
