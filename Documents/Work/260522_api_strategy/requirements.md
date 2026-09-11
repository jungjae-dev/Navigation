# LBS Provider 분리 — 요구사항

## 배경

API 전략 변경 ([api_strategy.md](api_strategy.md)):
- **검색**: 카카오 로컬 API (한국 POI 품질 우선)
- **길찾기**: Apple MapKit (카카오 모빌리티 도보 제휴 불필요, 무료)

현재는 "검색 + 경로"를 단일 provider(Kakao/Apple)로 통합 관리하지만,
전략 변경에 따라 **검색 provider와 길찾기 provider를 독립적으로 선택·관리**해야 한다.

---

## 현재 구조 (AS-IS)

```
LBSServiceProvider
  └─ providerType: Kakao | Apple  (단일 선택)

  Kakao 선택 시:
    search  = FallbackSearchService(primary: Kakao, fallback: Apple)
    route   = FallbackRouteService(primary: Kakao, fallback: Apple)
    geocoding = FallbackGeocodingService(primary: Kakao, fallback: Apple)

  Apple 선택 시:
    search  = AppleSearchService
    route   = AppleRouteService
    geocoding = AppleGeocodingService
```

개발자 메뉴: "검색/경로 제공자" 단일 항목 (Kakao / Apple 중 선택)

---

## 변경 구조 (TO-BE)

```
LBSServiceProvider
  ├─ searchProviderType: Kakao | Apple  (독립 선택)
  └─ routeProviderType:  Kakao | Apple  (독립 선택)

  searchProviderType=Kakao:
    search    = FallbackSearchService(primary: Kakao, fallback: 없음)
                ※ 한도 초과(429) 시 Apple 폴백 없이 throw + Notification 발송
    geocoding = FallbackGeocodingService(primary: Kakao, fallback: Apple)

  searchProviderType=Apple:
    search    = AppleSearchService
    geocoding = AppleGeocodingService

  routeProviderType=Kakao:
    route     = FallbackRouteService(primary: Kakao, fallback: Apple)

  routeProviderType=Apple:
    route     = AppleRouteService  (폴백 없음)
```

**기본값**: searchProviderType=Kakao, routeProviderType=Apple

---

## 요구사항

### 1. LBSServiceProvider 분리

- `providerType` (단일) → `searchProviderType` + `routeProviderType` 독립 분리
- UserDefaults 키: `lbs_provider` (삭제) → `search_provider` + `route_provider`
- 기존 `lbs_provider` 값 있으면 마이그레이션: search + route 모두 해당 값으로 초기화 후 기존 키 삭제
- `switchProvider(to:)` → `switchSearchProvider(to:)` + `switchRouteProvider(to:)` 분리
- search/geocoding은 항상 같은 provider (Kakao geocoding은 Kakao search와 묶임)

### 2. 개발자 메뉴 분리

- 현재: "검색/경로 제공자" 1개 항목
- 변경: "검색 제공자" + "경로 제공자" 2개 항목 (동일 섹션 내 2개 row)
- 각각 독립 picker: Kakao / Apple Maps 선택
- SettingsViewModel: `lbsProvider` → `searchProvider` + `routeProvider` Publisher 분리

### 3. 카카오 검색 429 처리 — 팝업 후 종료

카카오 검색 일 한도(100,000건) 초과 시 **Apple 폴백 없이** 팝업 표시 후 검색 중단.

> 이유: Apple 검색은 한국 POI 품질이 낮아 폴백 결과가 사용자 기대에 못 미침. 명확하게 알리는 게 낫다.

**동작 시나리오:**
- 검색 요청 → 카카오 API 호출 → 429 → 팝업 → 검색 실패
- 이후 모든 검색 시도마다 동일하게 반복 (사용자가 매번 인지 가능)
- 상태 저장 없음. 카카오 서버 측 한도가 초기화되면 자연히 정상 복구

**변경 사항:**
- `FallbackSearchService`의 `quotaExceeded` → Apple 폴백 로직 **제거**
- 대신 Notification 발송 후 throw
- Notification: `.lbsSearchQuotaExceeded`
- 팝업 내용:
  - 제목: "검색 한도 초과"
  - 메시지: "오늘 카카오 검색 한도에 도달했습니다.\n내일 자정에 자동으로 초기화됩니다."
  - 버튼: "확인"

### 4. 카카오 경로 429 팝업 (routeProviderType=Kakao 일 때만)

- `FallbackRouteService` 내부 로직(Kakao → Apple 폴백) **그대로 유지**
- 변경 사항은 Notification 이름 변경과 팝업 추가뿐
  - `.lbsProviderFallbackActivated` → `.lbsRouteFallbackActivated` (이름 변경)
  - 팝업 내용:
    - 제목: "경로 서비스 일시 제한"
    - 메시지: "카카오 경로 서비스가 일시적으로 제한됩니다.\n잠시 후 자동으로 복구됩니다."
    - 버튼: "확인"
- routeProviderType=Apple 이면 `AppleRouteService` 직접 사용 → Notification 발송 자체 없음 → 팝업 없음

---

## 변경 파일 목록

| 파일 | 변경 내용 |
|------|----------|
| `LBSServiceProvider.swift` | providerType 분리, makeServices 분리, 마이그레이션, `.lbsSearchProviderChanged` Notification 발송 |
| `FallbackSearchService.swift` | quotaExceeded → Apple 폴백 **제거**, `.lbsSearchQuotaExceeded` Notification 발송 후 throw |
| `FallbackRouteService.swift` | Notification 이름 변경 (`lbsProviderFallbackActivated` → `lbsRouteFallbackActivated`) |
| `SettingsViewModel.swift` | `lbsProvider` → `searchProvider` + `routeProvider` Publisher 분리 |
| `SettingsViewController.swift` | lbsProvider 1개 row → 2개 row 분리, picker 2개 |
| `HomeViewController.swift` | `.lbsSearchQuotaExceeded` + `.lbsRouteFallbackActivated` Notification 수신 → 팝업 표시 |
| `HomeDrawerViewController.swift` | `.lbsSearchProviderChanged` Notification 수신 → 카테고리 reloadData |

---

## 비변경 범위

- `KakaoRouteService.swift` — 삭제 없이 유지 (routeProviderType=Kakao 시 사용)
- `AppleRouteService.swift` — 변경 없음
- 경로 계산 로직 (`NavigationEngine`, `MapMatcher`) — 변경 없음
- 데이터 모델 (`FavoritePlace`, `SearchHistory`, `Recording`) — 변경 없음
