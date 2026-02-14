# Navigation App - Development Roadmap

## Phase 1: Foundation (MVP Core) - 2~3주

### Sprint 1: 프로젝트 셋업 + 지도 기본 (1주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 1.1 | Xcode 프로젝트 생성 | iOS 17+, SwiftUI App lifecycle, 폴더 구조 | 0.5일 |
| 1.2 | LocationService 구현 | CLLocationManager 래퍼, Combine publisher, 권한 처리 | 1일 |
| 1.3 | MapView 구현 | MKMapView UIViewRepresentable 래퍼, 현재 위치 표시 | 1일 |
| 1.4 | HomeView 기본 UI | 지도 + 검색 바 + 즐겨찾기 영역 레이아웃 | 1일 |
| 1.5 | Theme/디자인 토큰 | 색상, 폰트, 간격 등 미니멀 디자인 시스템 | 0.5일 |

**Sprint 1 산출물**: 앱 실행 → 지도에 현재 위치 표시

---

### Sprint 2: 검색 + 경로 탐색 (1주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 2.1 | SearchService 구현 | MKLocalSearchCompleter + MKLocalSearch 래퍼 | 1일 |
| 2.2 | SearchView UI | 검색 입력, 자동완성 리스트, 결과 선택 | 1일 |
| 2.3 | RouteService 구현 | MKDirections 래퍼, 대안 경로, 에러 처리 | 1일 |
| 2.4 | RoutePreviewView | 경로 미리보기 (폴리라인 표시, 경로 옵션, 안내 시작 버튼) | 1일 |
| 2.5 | SwiftData 모델 | FavoritePlace, SearchHistory 모델 + CRUD | 0.5일 |
| 2.6 | GeocodingService | CLGeocoder 래퍼 (주소 변환) | 0.5일 |

**Sprint 2 산출물**: 장소 검색 → 경로 표시 → 경로 선택

---

### Sprint 3: 네비게이션 안내 + Smooth Rendering (1.5주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 3.1 | GuidanceEngine 기본 | 경로 시작/정지, 현재 스텝 추적, 진행률 계산 | 1.5일 |
| 3.2 | OffRouteDetector | 경로 이탈 감지 + 자동 재경로 탐색 | 1일 |
| 3.3 | VoiceGuidanceService | AVSpeechSynthesizer TTS + 안내 텍스트 생성 | 1일 |
| 3.4 | NavigationView UI | 회전 안내 배너 + 지도 + 하단 정보 바 | 1일 |
| 3.5 | MapCamera 기본 | 진행 방향 카메라 추적 + 수동 전환 | 0.5일 |
| 3.6 | MapInterpolator | CADisplayLink 기반 위치/방향/카메라 프레임 보간 | 1.5일 |
| 3.7 | 회전 지점 팝업 안내 | TurnPointPopupService + 정북 2D 팝업 MKMapView + 실시간 위치 반영 | 1일 |

**Sprint 3 산출물**: 부드러운 지도 표현 + 분기점 안내 포함 전체 플로우 완성

---

## Phase 2: CarPlay + 안정화 - 2~3주

### Sprint 4: CarPlay 기본 (1주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 4.1 | CarPlay 프로젝트 설정 | Entitlements, Scene 등록, Info.plist | 0.5일 |
| 4.2 | CarPlayService 기본 | CPMapTemplate + CPTemplateApplicationSceneDelegate | 1일 |
| 4.3 | CarPlay 검색 | CPSearchTemplate + 검색 결과 표시 | 1일 |
| 4.4 | CarPlay 네비게이션 | CPNavigationSession + CPManeuver 연동 | 1.5일 |
| 4.5 | iPhone ↔ CarPlay 동기화 | 상태 공유, 양방향 안내 시작/종료 | 1일 |

**Sprint 4 산출물**: CarPlay에서 검색 → 안내 동작

---

### Sprint 5: 안정화 + 품질 (1주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 5.1 | Unit Tests | OffRouteDetector, GuidanceEngine, StepTracker 테스트 | 1일 |
| 5.2 | GPX 시뮬레이션 테스트 | 다양한 경로 GPX 파일로 시뮬레이션 | 1일 |
| 5.3 | 에러 핸들링 강화 | 네트워크 끊김, GPS 불량, 권한 거부 등 | 1일 |
| 5.4 | UI 폴리싱 | 애니메이션, 다크모드, 접근성 | 1일 |
| 5.5 | 메모리/배터리 최적화 | Instruments 프로파일링, 위치 필터 조정 | 1일 |

**Sprint 5 산출물**: 안정적인 MVP 완성

---

### Sprint 6: 부가 기능 + 특화 기능 (2주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 6.1 | 즐겨찾기 관리 | 추가/삭제/편집, 집/회사 빠른 설정 | 1일 |
| 6.2 | 최근 검색/안내 기록 | 검색 기록 관리, 최근 경로 재안내 | 0.5일 |
| 6.3 | 설정 화면 | 음성 ON/OFF, 이동수단 기본값, 단위 설정 | 0.5일 |
| 6.4 | 도보 모드 | 도보 전용 안내 타이밍, 카메라, UI 조정 | 1일 |
| 6.5 | 햅틱 피드백 | 회전 지점, 이탈, 도착 시 진동 | 0.5일 |
| 6.6 | CarPlay 즐겨찾기/최근 | CPListTemplate으로 빠른 접근 | 0.5일 |
| 6.7 | 커스텀 차량 아이콘 (프리셋) | 기본 제공 차량 아이콘 세트 (세단/SUV/스포츠카) + 설정 UI | 0.5일 |
| 6.8 | Lift Subject 차량 아이콘 | Vision API 배경 제거 + 사진 선택 + 아이콘 적용 | 1.5일 |
| 6.9 | 3D 차량 모델 렌더링 | SceneKit 오버레이 + USDZ 로드 + 지도 카메라 동기화 | 2일 |
| 6.10 | 가상 주행 엔진 | VirtualDriveEngine + 경로 시뮬레이션 + 재생 컨트롤 UI | 1.5일 |
| 6.11 | 주차장 진입 안내 | 목적지 근처 줌인 + 건물 3D 뷰 + 진입 방향 마커 | 1일 |

**Sprint 6 산출물**: 특화 기능 포함 실사용 가능한 완성도

---

### Sprint 7: 개발자 도구 (1주)

| # | 태스크 | 상세 | 예상 |
|---|--------|------|------|
| 7.1 | GPX 녹화 기능 | GPXRecorder + 주행 중 GPS 데이터 GPX 파일 저장 | 1일 |
| 7.2 | GPX 재생 기능 | GPXPlayer + GPXParser + 가상 위치 주입 재생 | 1.5일 |
| 7.3 | GPX 파일 관리 | 파일 목록/삭제/공유 + SwiftData 메타데이터 | 0.5일 |
| 7.4 | 개발자 메뉴 UI | DevToolsView + 녹화/재생 컨트롤 + 설정에서 접근 | 1일 |
| 7.5 | 디버그 오버레이 | GPS 정확도/속도/좌표 실시간 표시 (개발 모드) | 0.5일 |

**Sprint 7 산출물**: 개발/디버깅용 GPS 녹화·재생 도구 완성

---

## Phase 3: 고급 기능 - 2~3주 (선택)

| # | 기능 | 상세 | 우선순위 |
|---|------|------|---------|
| 7.1 | 경유지 추가 | 다중 목적지, 드래그 순서 변경 | 높음 |
| 7.2 | Live Activity | 잠금화면에 남은 거리/시간 표시 | 높음 |
| 7.3 | 위젯 | 자주 가는 곳 바로 안내 위젯 | 중간 |
| 7.4 | Siri Shortcuts | "집으로 안내해줘" 음성 명령 | 중간 |
| 7.5 | 도착 시간 공유 | 메시지로 ETA 공유 | 낮음 |
| 7.6 | 야간 지도 모드 | 어두운 지도 스타일 | 중간 |
| 7.7 | 속도 제한 표시 | 현재 도로 제한 속도 (가능한 경우) | 낮음 |
| 7.8 | 주차 위치 기억 | 목적지 도착 시 주차 위치 저장 | 낮음 |

---

## Phase 4: 확장 - 추후

| # | 기능 | 상세 |
|---|------|------|
| 8.1 | Apple Watch 연동 | 도보 안내 시 손목에서 방향 안내 |
| 8.2 | 오프라인 지도 | Mapbox 검토, 지도 다운로드 |
| 8.3 | 교통 정보 | 실시간 교통 반영 경로 |
| 8.4 | PaceTracker 연동 | 운동 장소까지 네비 → 운동 기록 자연스러운 전환 |

---

## 전체 타임라인 요약

```
Week 1     [Sprint 1] 프로젝트 셋업 + 지도 ──────────── 🗺️ 지도 표시
Week 2     [Sprint 2] 검색 + 경로 탐색 ─────────────── 🔍 경로 미리보기
Week 3-4   [Sprint 3] 안내 + Smooth + 분기점 ────────── 🧭 MVP 완성!
Week 5     [Sprint 4] CarPlay ───────────────────────── 🚗 CarPlay 동작
Week 6     [Sprint 5] 안정화 + 테스트 ──────────────── ✅ 품질 확보
Week 7-8   [Sprint 6] 부가 + 특화 기능 ─────────────── ⭐ 차량아이콘/가상주행
Week 9     [Sprint 7] 개발자 도구 ───────────────────── 🛠️ GPX 녹화/재생
Week 10-12 [Phase 3]  고급 기능 ─────────────────────── 🚀 앱스토어 출시 수준
```

---

## 마일스톤

| 마일스톤 | 시점 | 기준 |
|---------|------|------|
| **M1: 지도 동작** | Week 1 | 앱 실행, 현재 위치 지도 표시 |
| **M2: 경로 탐색** | Week 2 | 검색 → 경로 표시 → 경로 선택 |
| **M3: MVP 완성** | Week 3-4 | 부드러운 지도 + 분기점 안내 포함 전체 네비게이션 플로우 |
| **M4: CarPlay** | Week 5 | CarPlay 시뮬레이터에서 동작 |
| **M5: 특화 기능** | Week 8 | 커스텀 차량 아이콘 + 가상 주행 + 주차장 안내 |
| **M6: DevTools** | Week 9 | GPS 녹화/재생 개발자 도구 완성 |
| **M7: Beta Ready** | Week 9 | TestFlight 배포 가능 |
| **M8: Release** | Week 12 | App Store 제출 가능 |

---

## 리스크 & 대응

| 리스크 | 영향 | 대응 |
|--------|------|------|
| Apple Maps 한국 데이터 부족 | 경로 품질 저하 | 실제 테스트로 품질 확인, 대안 경로 활용 |
| CarPlay Entitlement 승인 지연 | CarPlay 개발 지연 | 시뮬레이터로 선개발, 승인 후 실기기 테스트 |
| MKDirections 요청 제한 | 잦은 재탐색 시 throttle | debounce 적용, 캐싱 전략 |
| 배터리 소모 | 사용자 불만 | 거리 필터, 정확도 단계 조절 |
| 백그라운드 제한 (iOS 정책) | 안내 끊김 | Background Modes 올바른 설정, 테스트 |
| Vision Lift Subject 시뮬레이터 미지원 | 개발 중 테스트 제한 | 실기기 테스트 필수, Mock 이미지로 우회 |
| SceneKit 3D 오버레이 성능 | 네비 중 렌더링 부하 | 단일 모델 + LOD 적용, Instruments 프로파일링 |
| CADisplayLink 보간 + 지도 렌더링 | 메인 스레드 부하 | 보간 계산 최소화, 프레임 드랍 모니터링 |
| 팝업 MKMapView 메모리 | 두 개의 MKMapView 동시 운용 | 팝업 비활성 시 해제, 필요 시 재생성 |
