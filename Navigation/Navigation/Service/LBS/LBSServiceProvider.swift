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

    private(set) var providerType: LBSProviderType

    private(set) var search: SearchProviding
    private(set) var route: RouteProviding
    private(set) var geocoding: GeocodingProviding

    private init() {
        let savedType = UserDefaults.standard.string(forKey: "lbs_provider")
            .flatMap(LBSProviderType.init(rawValue:)) ?? .apple

        self.providerType = savedType
        (search, route, geocoding) = Self.makeServices(for: savedType)
    }

    func switchProvider(to type: LBSProviderType) {
        guard type != providerType else { return }
        UserDefaults.standard.set(type.rawValue, forKey: "lbs_provider")
        providerType = type
        (search, route, geocoding) = Self.makeServices(for: type)
    }

    // MARK: - Private

    private static func makeServices(
        for type: LBSProviderType
    ) -> (SearchProviding, RouteProviding, GeocodingProviding) {
        switch type {
        case .apple:
            return (AppleSearchService(), AppleRouteService(), AppleGeocodingService())
        case .kakao:
            let appleSearch = AppleSearchService()
            let appleRoute = AppleRouteService()
            let appleGeocoding = AppleGeocodingService()
            return (
                FallbackSearchService(primary: KakaoSearchService(), fallback: appleSearch),
                FallbackRouteService(primary: KakaoRouteService(), fallback: appleRoute),
                FallbackGeocodingService(primary: KakaoGeocodingService(), fallback: appleGeocoding)
            )
        }
    }
}
