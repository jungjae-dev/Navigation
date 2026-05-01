# LBS 서비스 추상화 레이어 도입

## 개요
Apple MapKit API(MKRoute, MKMapItem, MKLocalSearch 등)에 직접 의존하는 서비스 레이어를
프로토콜 기반 추상화로 전환하여, **Kakao / Apple / 기타 Provider를 교체 가능**하게 한다.

지도 렌더링(MKMapView)은 Apple Maps를 그대로 유지하고,
**검색(Search), 경로(Route), 지오코딩(Geocoding)** API만 추상화 대상으로 한다.

## 아키텍처

```
┌─────────────────────────────────────────────────┐
│                    App Layer                     │
│  ViewModel / Coordinator / CarPlay / View        │
│  (Place, Route, RouteStep, SearchCompletion)     │
└──────────────────────┬──────────────────────────┘
                       │ Protocol
┌──────────────────────┴──────────────────────────┐
│              LBS Service Layer                   │
│  SearchProviding / RouteProviding / Geocoding    │
├────────────┬────────────┬───────────────────────┤
│  Apple     │  Kakao     │  Fallback Wrapper      │
│  Impl.     │  Impl.     │  (Primary → Fallback)  │
└────────────┴────────────┴───────────────────────┘
                       │
┌──────────────────────┴──────────────────────────┐
│              Map Rendering (MKMapView)            │
│  Route.mkPolyline / Place.mkMapItem 변환          │
│  (Apple Maps 유지, 변환은 View 레이어에서만)        │
└─────────────────────────────────────────────────┘
```

## Phase 구성

| Phase | 내용 | 문서 | 선행 조건 |
|-------|------|------|-----------|
| **1** | 앱 모델 + 프로토콜 + DI 컨테이너 | [Phase1_Foundation.md](Phase1_Foundation.md) | 없음 |
| **2** | Apple 구현체 래핑 + 변환 유틸 | [Phase2_AppleImplementation.md](Phase2_AppleImplementation.md) | Phase 1 |
| **3** | 소비자 코드 마이그레이션 (ViewModel, Engine, Coordinator, CarPlay, View) | [Phase3_ConsumerMigration.md](Phase3_ConsumerMigration.md) | Phase 2 |
| **4** | Kakao 구현체 추가 | [Phase4_KakaoImplementation.md](Phase4_KakaoImplementation.md) | Phase 3 |
| **5** | Fallback 래퍼 + 설정 UI + 테스트 | [Phase5_FallbackAndTest.md](Phase5_FallbackAndTest.md) | Phase 4 |

## 핵심 모델 요약

| 앱 모델 | 대체 대상 (Apple) | 용도 |
|---------|-------------------|------|
| `Place` | `MKMapItem` | 검색 결과, 목적지, 즐겨찾기 |
| `Route` | `MKRoute` | 경로 (거리, 시간, polyline, steps) |
| `RouteStep` | `MKRoute.Step` | 안내 지점 (지시문, 거리, 좌표) |
| `SearchCompletion` | `MKLocalSearchCompletion` | 검색 자동완성 |

## 프로토콜 요약

| 프로토콜 | 메서드 |
|---------|--------|
| `SearchProviding` | updateQuery, search(for:), search(query:), completionsPublisher |
| `RouteProviding` | calculateRoutes, calculateETA, cancelCurrentRequest |
| `GeocodingProviding` | reverseGeocode, geocode |

## 영향 범위 요약

**총 수정 대상 파일: ~25개**

| 카테고리 | 파일 수 | 주요 파일 |
|---------|---------|-----------|
| 서비스 (새로 생성) | 10+ | LBS/Model/*, LBS/Protocol/*, LBS/Apple/*, LBS/Kakao/* |
| 엔진 | 3 | GuidanceEngine, OffRouteDetector, VirtualDriveEngine |
| ViewModel | 3 | SearchViewModel, RoutePreviewViewModel, NavigationViewModel |
| Coordinator | 1 | AppCoordinator |
| CarPlay | 4 | SceneDelegate, SearchHandler, NavigationHandler, FavoritesHandler |
| View/VC | 6+ | MapVC, SearchVC, SearchResultDrawerVC, POIDetailVC, RoutePreviewDrawerVC 등 |
| Session | 1 | NavigationSessionManager |
| 유틸 | 2 | GuidanceTextBuilder, DistanceCalculator |

## 검증 체크리스트 (전체)

### Phase 1 완료 시
- [ ] 모델 파일 컴파일 성공
- [ ] 프로토콜 정의가 기존 서비스 인터페이스를 커버

### Phase 2 완료 시
- [ ] Apple 구현체가 프로토콜 준수
- [ ] Model Converter 라운드트립 테스트 통과

### Phase 3 완료 시 (핵심 마일스톤)
- [ ] 전체 빌드 성공
- [ ] 검색 → 경로 → 네비게이션 플로우 정상
- [ ] CarPlay 플로우 정상
- [ ] `import MapKit`이 Service/LBS/Apple/과 Map/ 레이어에만 존재
- [ ] 기존 서비스 파일 삭제 완료

### Phase 4 완료 시
- [ ] Kakao 검색/경로/지오코딩 API 호출 성공
- [ ] Kakao Route polyline 지도 표시 정상
- [ ] Provider 전환으로 Kakao 경로 주행 가능

### Phase 5 완료 시 (최종)
- [ ] Fallback 자동 전환 동작
- [ ] 설정 UI에서 Provider 선택 가능
- [ ] 전체 단위 테스트 통과
- [ ] E2E 플로우 테스트 통과

## 주의사항

1. **Phase 2-3은 반드시 동시에 완료** — Apple 구현체와 소비자 코드 전환이 모두 끝나야 기존 서비스 삭제 가능
2. **Kakao 도보 길찾기 미지원** — FallbackService에서 Apple로 자동 전환
3. **Kakao Mobility 월 5,000건 제한** — 개발/테스트 시 할당량 소모 주의
4. **CarPlay MKMapView 유지** — CPMapTemplate의 지도는 Apple Maps만 가능
5. **providerRawData 필드** — 디버깅 및 원본 API 호출에 필요, production에서는 nil 가능
