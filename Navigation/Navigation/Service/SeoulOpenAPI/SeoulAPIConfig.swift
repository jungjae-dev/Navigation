import Foundation

enum SeoulAPIConfig {

    /// 서울 열린데이터광장 일반 인증키 (Info.plist 주입)
    static var apiKey: String {
        Bundle.main.infoDictionary?["SEOUL_OPEN_API_KEY"] as? String ?? ""
    }

    enum BaseURL {
        /// openapi.seoul.go.kr:8088 — HTTP (HTTPS 미지원 엔드포인트)
        static let openAPI = "http://openapi.seoul.go.kr:8088"
    }
}
