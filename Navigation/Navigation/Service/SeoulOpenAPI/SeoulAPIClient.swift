import Foundation
import OSLog

private let seoulAPILogger = Logger(subsystem: "nav.api", category: "SeoulAPI")

/// 서울 열린데이터광장 OpenAPI 공통 클라이언트
/// URL: http://openapi.seoul.go.kr:8088/{KEY}/{TYPE}/{SERVICE}/{START}/{END}/{OPTIONAL_PATHS}
final class SeoulAPIClient {

    static let shared = SeoulAPIClient()

    private init() {}

    /// 공통 호출 메서드
    /// - Parameters:
    ///   - service: API 서비스명 (예: "bikeList")
    ///   - startIndex: 시작 인덱스 (1-based)
    ///   - endIndex: 종료 인덱스 (양쪽 포함)
    ///   - extraPaths: 추가 path 파라미터 (필터링용)
    func request<T: Decodable>(
        service: String,
        startIndex: Int,
        endIndex: Int,
        extraPaths: [String] = [],
        responseType: T.Type
    ) async throws -> T {
        let key = SeoulAPIConfig.apiKey
        guard !key.isEmpty else {
            seoulAPILogger.error("SEOUL_OPEN_API_KEY 누락")
            throw SeoulAPIError.missingAPIKey
        }

        var pathComponents = [key, "json", service, "\(startIndex)", "\(endIndex)"]
        pathComponents.append(contentsOf: extraPaths)
        let pathSuffix = "/" + pathComponents.joined(separator: "/") + "/"
        let urlString = SeoulAPIConfig.BaseURL.openAPI + pathSuffix

        guard let url = URL(string: urlString) else {
            throw SeoulAPIError.network("Invalid URL: \(urlString)")
        }

        seoulAPILogger.debug("GET \(service)/\(startIndex)/\(endIndex, privacy: .public)\(extraPaths.isEmpty ? "" : "/\(extraPaths.joined(separator: "/"))", privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw SeoulAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SeoulAPIError.network("Bad response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SeoulAPIError.http(http.statusCode)
        }

        // 성공 응답이어도 body에 INFO-100/INFO-200 등 결과 코드가 올 수 있음 → 호출자가 검사
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            seoulAPILogger.error("Decoding error: \(error.localizedDescription, privacy: .public)")
            throw SeoulAPIError.decoding(error)
        }
    }
}
