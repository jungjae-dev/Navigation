import Foundation

enum KakaoAPIConfig {

    static var restAPIKey: String {
        Bundle.main.infoDictionary?["KAKAO_REST_API_KEY"] as? String ?? ""
    }

    static var mobilityAppKey: String {
        Bundle.main.infoDictionary?["KAKAO_MOBILITY_APP_KEY"] as? String ?? ""
    }

    enum BaseURL {
        static let local = "https://dapi.kakao.com"
        static let mobility = "https://apis-navi.kakaomobility.com"
    }
}
