import Foundation

enum LBSProviderType: String, CaseIterable, Sendable {
    case apple
    case kakao

    var displayName: String {
        switch self {
        case .apple: return "Apple Maps"
        case .kakao: return "Kakao"
        }
    }
}

final class LBSServiceProvider {

    static let shared = LBSServiceProvider()

    private(set) var searchProviderType: LBSProviderType
    private(set) var routeProviderType: LBSProviderType

    private(set) var search: SearchProviding
    private(set) var route: RouteProviding
    private(set) var geocoding: GeocodingProviding

    private init() {
        // 마이그레이션: 기존 lbs_provider 키 → route_provider만 인계, search는 항상 kakao
        if let legacy = UserDefaults.standard.string(forKey: "lbs_provider") {
            UserDefaults.standard.set(legacy, forKey: "route_provider")
            UserDefaults.standard.removeObject(forKey: "lbs_provider")
        }

        let savedSearch = UserDefaults.standard.string(forKey: "search_provider")
            .flatMap(LBSProviderType.init(rawValue:)) ?? .kakao
        let savedRoute = UserDefaults.standard.string(forKey: "route_provider")
            .flatMap(LBSProviderType.init(rawValue:)) ?? .apple

        self.searchProviderType = savedSearch
        self.routeProviderType = savedRoute
        self.search = Self.makeSearchService(for: savedSearch)
        self.route = Self.makeRouteService(for: savedRoute)
        self.geocoding = Self.makeGeocodingService(for: savedSearch)
    }

    func switchSearchProvider(to type: LBSProviderType) {
        guard type != searchProviderType else { return }
        UserDefaults.standard.set(type.rawValue, forKey: "search_provider")
        searchProviderType = type
        search = Self.makeSearchService(for: type)
        geocoding = Self.makeGeocodingService(for: type)
        NotificationCenter.default.post(name: .lbsSearchProviderChanged, object: nil)
    }

    func switchRouteProvider(to type: LBSProviderType) {
        guard type != routeProviderType else { return }
        UserDefaults.standard.set(type.rawValue, forKey: "route_provider")
        routeProviderType = type
        route = Self.makeRouteService(for: type)
    }

    // MARK: - Private

    private static func makeSearchService(for type: LBSProviderType) -> SearchProviding {
        switch type {
        case .kakao:
            return FallbackSearchService(primary: KakaoSearchService())
        case .apple:
            return AppleSearchService()
        }
    }

    private static func makeRouteService(for type: LBSProviderType) -> RouteProviding {
        switch type {
        case .kakao:
            return FallbackRouteService(primary: KakaoRouteService(), fallback: AppleRouteService())
        case .apple:
            return AppleRouteService()
        }
    }

    private static func makeGeocodingService(for type: LBSProviderType) -> GeocodingProviding {
        switch type {
        case .kakao:
            return FallbackGeocodingService(primary: KakaoGeocodingService(), fallback: AppleGeocodingService())
        case .apple:
            return AppleGeocodingService()
        }
    }
}

extension Notification.Name {
    static let lbsSearchProviderChanged = Notification.Name("lbsSearchProviderChanged")
    static let lbsSearchQuotaExceeded = Notification.Name("lbsSearchQuotaExceeded")
    static let lbsRouteFallbackActivated = Notification.Name("lbsRouteFallbackActivated")
}
