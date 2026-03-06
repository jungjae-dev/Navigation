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
            // Phase 2에서 AppleSearchService, AppleRouteService, AppleGeocodingService로 교체
            fatalError("Phase 2에서 Apple 구현체 연결 필요")
        case .kakao:
            // Phase 4에서 구현
            fatalError("Phase 4에서 Kakao 구현체 연결 필요")
        }
    }
}
