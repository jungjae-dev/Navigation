import Foundation

enum LBSProviderType: String, CaseIterable, Sendable {
    case apple
    case kakao
}

final class LBSServiceProvider {

    static let shared = LBSServiceProvider()

    let providerType: LBSProviderType

    private(set) var search: SearchProviding
    private(set) var route: RouteProviding
    private(set) var geocoding: GeocodingProviding

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
            // Phase 4에서 Kakao 구현체 추가, 현재는 Apple fallback
            search = AppleSearchService()
            route = AppleRouteService()
            geocoding = AppleGeocodingService()
        }
    }
}
