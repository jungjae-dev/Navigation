# Phase 5: Fallback / 설정 UI / 테스트

## 목표
1. 할당량 초과 시 자동 fallback 메커니즘 구현
2. 사용자가 Provider를 선택할 수 있는 설정 UI 추가
3. 프로토콜 기반 Mock을 활용한 단위 테스트 작성

---

## 5-1. FallbackService 래퍼

### 개념
```
사용자 요청
    ↓
FallbackRouteService
    ├─ primary: KakaoRouteService
    │     ├─ 성공 → 결과 반환
    │     └─ quotaExceeded → fallback으로 전환
    └─ fallback: AppleRouteService
          └─ 결과 반환
```

### 파일 위치
```
Navigation/Service/LBS/Fallback/
├── FallbackSearchService.swift
├── FallbackRouteService.swift
└── FallbackGeocodingService.swift
```

### FallbackRouteService
```swift
final class FallbackRouteService: RouteProviding {
    private let primary: RouteProviding
    private let fallback: RouteProviding
    private var isPrimaryAvailable = true

    // 할당량 초과 후 복구 시도 간격
    private let recoveryInterval: TimeInterval = 3600  // 1시간
    private var lastQuotaExceededDate: Date?

    init(primary: RouteProviding, fallback: RouteProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        // 복구 시도
        checkRecovery()

        if isPrimaryAvailable {
            do {
                return try await primary.calculateRoutes(
                    from: origin, to: destination, transportMode: transportMode
                )
            } catch let error as LBSError where error == .quotaExceeded {
                markPrimaryUnavailable()
                return try await fallback.calculateRoutes(
                    from: origin, to: destination, transportMode: transportMode
                )
            } catch let error as LBSError where error == .noRoutesFound {
                // Kakao 도보 미지원 등 → fallback
                return try await fallback.calculateRoutes(
                    from: origin, to: destination, transportMode: transportMode
                )
            }
        }

        return try await fallback.calculateRoutes(
            from: origin, to: destination, transportMode: transportMode
        )
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        checkRecovery()
        if isPrimaryAvailable {
            do {
                return try await primary.calculateETA(from: origin, to: destination)
            } catch let error as LBSError where error == .quotaExceeded {
                markPrimaryUnavailable()
                return try await fallback.calculateETA(from: origin, to: destination)
            }
        }
        return try await fallback.calculateETA(from: origin, to: destination)
    }

    func cancelCurrentRequest() {
        primary.cancelCurrentRequest()
        fallback.cancelCurrentRequest()
    }

    // MARK: - Private

    private func markPrimaryUnavailable() {
        isPrimaryAvailable = false
        lastQuotaExceededDate = Date()
        // 사용자에게 알림 (선택적)
        NotificationCenter.default.post(
            name: .lbsProviderFallbackActivated, object: nil
        )
    }

    private func checkRecovery() {
        guard !isPrimaryAvailable,
              let lastDate = lastQuotaExceededDate,
              Date().timeIntervalSince(lastDate) > recoveryInterval else { return }
        isPrimaryAvailable = true
    }
}

extension Notification.Name {
    static let lbsProviderFallbackActivated = Notification.Name("lbsProviderFallbackActivated")
}
```

### FallbackSearchService / FallbackGeocodingService
동일한 패턴으로 구현. 검색은 할당량이 넉넉하므로 단순 try-catch fallback.

---

## 5-2. LBSServiceProvider Fallback 모드 통합

```swift
final class LBSServiceProvider {
    // ...

    private init() {
        let savedType = UserDefaults.standard.string(forKey: "lbs_provider")
            .flatMap(LBSProviderType.init(rawValue:)) ?? .apple

        self.providerType = savedType

        switch savedType {
        case .apple:
            search = AppleSearchService()
            route = AppleRouteService()
            geocoding = AppleGeocodingService()
        case .kakao:
            let kakaoSearch = KakaoSearchService()
            let kakaoRoute = KakaoRouteService()
            let kakaoGeocoding = KakaoGeocodingService()
            let appleSearch = AppleSearchService()
            let appleRoute = AppleRouteService()
            let appleGeocoding = AppleGeocodingService()

            search = FallbackSearchService(primary: kakaoSearch, fallback: appleSearch)
            route = FallbackRouteService(primary: kakaoRoute, fallback: appleRoute)
            geocoding = FallbackGeocodingService(primary: kakaoGeocoding, fallback: appleGeocoding)
        }
    }

    func switchProvider(to type: LBSProviderType) {
        UserDefaults.standard.set(type.rawValue, forKey: "lbs_provider")
        // 런타임 전환: 서비스 재생성
        // 주의: 진행 중인 네비게이션이 있으면 전환 불가 처리
    }
}
```

---

## 5-3. 설정 UI

### 기존 SettingsViewController에 Provider 선택 추가

**SettingsViewModel 확장:**
```swift
// 기존 SettingsViewModel에 추가
let lbsProvider = CurrentValueSubject<LBSProviderType, Never>(
    LBSServiceProvider.shared.providerType
)

func setLBSProvider(_ type: LBSProviderType) {
    LBSServiceProvider.shared.switchProvider(to: type)
    lbsProvider.send(type)
}
```

**UI 구성:**
- 설정 화면에 "위치 서비스 제공자" 섹션 추가
- Apple Maps / Kakao 선택 (UISegmentedControl 또는 UITableView row)
- Kakao 선택 시 API 키 미설정이면 경고
- 네비게이션 진행 중에는 전환 비활성화

### Fallback 알림 UI
```swift
// AppCoordinator에서 Notification 수신
NotificationCenter.default.addObserver(
    forName: .lbsProviderFallbackActivated,
    object: nil,
    queue: .main
) { [weak self] _ in
    // 토스트 또는 배너: "API 할당량 초과로 Apple Maps로 전환되었습니다"
}
```

---

## 5-4. 단위 테스트

### Mock 서비스

프로토콜 기반이므로 Mock 생성이 간단:

```swift
// NavigationTests/Mock/MockRouteService.swift
final class MockRouteService: RouteProviding {
    var mockRoutes: [Route] = []
    var mockETA: TimeInterval = 600
    var shouldThrow: LBSError?
    var calculateRoutesCallCount = 0

    func calculateRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> [Route] {
        calculateRoutesCallCount += 1
        if let error = shouldThrow { throw error }
        return mockRoutes
    }

    func calculateETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> TimeInterval {
        if let error = shouldThrow { throw error }
        return mockETA
    }

    func cancelCurrentRequest() {}
}
```

```swift
// NavigationTests/Mock/MockSearchService.swift
final class MockSearchService: SearchProviding {
    let completionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let queryCompletionsPublisher = CurrentValueSubject<[SearchCompletion], Never>([])
    let isSearchingPublisher = CurrentValueSubject<Bool, Never>(false)
    let errorPublisher = PassthroughSubject<Error, Never>()

    var mockSearchResults: [Place] = []

    func updateRegion(_ region: MKCoordinateRegion) {}
    func updateQuery(_ fragment: String) {}
    func search(for completion: SearchCompletion) async throws -> [Place] { mockSearchResults }
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] { mockSearchResults }
    func cancelCurrentSearch() {}
}
```

### 테스트 케이스

#### 모델 테스트
```swift
@Test func routeFormattedDistance() {
    let route = Route(id: "1", distance: 1500, ...)
    #expect(route.formattedDistance == "1.5km")
}

@Test func routeFormattedTravelTime() {
    let route = Route(id: "1", ..., expectedTravelTime: 3900, ...)
    #expect(route.formattedTravelTime == "1시간 5분")
}
```

#### GuidanceEngine 테스트
```swift
@Test func guidanceEngineUsesRouteProviding() async {
    let mockRoute = MockRouteService()
    mockRoute.mockRoutes = [TestFixtures.sampleRoute]

    let engine = GuidanceEngine(
        locationService: .shared,
        routeService: mockRoute,   // 프로토콜 주입
        voiceService: VoiceGuidanceService(),
        offRouteDetector: OffRouteDetector()
    )

    engine.startNavigation(with: TestFixtures.sampleRoute)
    #expect(engine.navigationStatePublisher.value == .navigating)
}
```

#### Fallback 테스트
```swift
@Test func fallbackRouteServiceSwitchesOnQuotaExceeded() async throws {
    let primary = MockRouteService()
    primary.shouldThrow = .quotaExceeded

    let fallback = MockRouteService()
    fallback.mockRoutes = [TestFixtures.sampleRoute]

    let service = FallbackRouteService(primary: primary, fallback: fallback)

    let routes = try await service.calculateRoutes(
        from: .init(latitude: 37.5, longitude: 127.0),
        to: .init(latitude: 37.55, longitude: 127.05),
        transportMode: .automobile
    )

    #expect(routes.count == 1)
    #expect(primary.calculateRoutesCallCount == 1)
}

@Test func fallbackRecoveryAfterInterval() async throws {
    let primary = MockRouteService()
    primary.shouldThrow = .quotaExceeded

    let fallback = MockRouteService()
    fallback.mockRoutes = [TestFixtures.sampleRoute]

    let service = FallbackRouteService(primary: primary, fallback: fallback)

    // 첫 호출: primary 실패 → fallback
    _ = try await service.calculateRoutes(...)

    // primary 복구
    primary.shouldThrow = nil
    primary.mockRoutes = [TestFixtures.sampleRoute]

    // 복구 간격 시뮬레이션 (테스트용 interval 주입)
    service.lastQuotaExceededDate = Date().addingTimeInterval(-3601)

    let routes = try await service.calculateRoutes(...)
    #expect(primary.calculateRoutesCallCount == 2) // primary 재시도
}
```

#### Converter 테스트
```swift
@Test func kakaoRouteConverterExtractsPolyline() {
    let kakaoRoute = KakaoRouteResponse.KakaoRoute(
        resultCode: 0,
        resultMessage: "",
        summary: .init(distance: 5000, duration: 600),
        sections: [.init(distance: 5000, duration: 600, roads: [
            .init(vertexes: [127.0, 37.5, 127.01, 37.51, 127.02, 37.52])
        ], guides: [])]
    )

    let route = KakaoModelConverter.route(from: kakaoRoute)
    #expect(route.polylineCoordinates.count == 3)
    #expect(route.distance == 5000)
}
```

---

## 5-5. TestFixtures

```swift
// NavigationTests/Fixture/TestFixtures.swift
enum TestFixtures {
    static let sampleRoute = Route(
        id: "test-1",
        distance: 5000,
        expectedTravelTime: 600,
        name: "테스트 경로",
        steps: [
            RouteStep(instructions: "직진", distance: 3000, polylineCoordinates: [...]),
            RouteStep(instructions: "우회전하세요", distance: 1500, polylineCoordinates: [...]),
            RouteStep(instructions: "목적지", distance: 500, polylineCoordinates: [...]),
        ],
        polylineCoordinates: [...],
        transportMode: .automobile
    )

    static let samplePlace = Place(
        name: "강남역",
        coordinate: CLLocationCoordinate2D(latitude: 37.4979, longitude: 127.0276),
        address: "서울 강남구 강남대로 396",
        phoneNumber: nil,
        category: "지하철역",
        providerRawData: nil
    )
}
```

---

## 검증 항목

| # | 검증 내용 | 방법 |
|---|---|---|
| V5-1 | FallbackRouteService: primary 성공 시 fallback 미호출 | 단위 테스트 |
| V5-2 | FallbackRouteService: quotaExceeded 시 fallback 호출 | 단위 테스트 |
| V5-3 | FallbackRouteService: noRoutesFound (도보) 시 fallback 호출 | 단위 테스트 |
| V5-4 | FallbackRouteService: 복구 간격 후 primary 재시도 | 단위 테스트 |
| V5-5 | FallbackSearchService 동일 패턴 동작 확인 | 단위 테스트 |
| V5-6 | 설정 UI에서 Provider 전환 가능 | 시뮬레이터 수동 테스트 |
| V5-7 | Provider 전환 후 검색/경로 정상 동작 | 시뮬레이터 수동 테스트 |
| V5-8 | 네비게이션 진행 중 Provider 전환 비활성화 | 시뮬레이터 수동 테스트 |
| V5-9 | Fallback 활성화 시 사용자 알림 표시 | 시뮬레이터 수동 테스트 |
| V5-10 | MockRouteService로 GuidanceEngine 단위 테스트 통과 | `xcodebuild test` |
| V5-11 | MockSearchService로 SearchViewModel 단위 테스트 통과 | `xcodebuild test` |
| V5-12 | Converter 테스트 (Apple, Kakao 양쪽) 통과 | `xcodebuild test` |
| V5-13 | 전체 테스트 스위트 통과 | `xcodebuild test` |
| V5-14 | 전체 앱 E2E 플로우 (검색→경로→네비게이션→도착) 정상 | 시뮬레이터 수동 테스트 |
