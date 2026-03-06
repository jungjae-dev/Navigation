import Foundation

final class KakaoAPIClient {

    static let shared = KakaoAPIClient()

    private init() {}

    func request<T: Decodable>(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem],
        apiKey: String
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw LBSError.networkError("Invalid URL: \(baseURL + path)")
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw LBSError.networkError("Invalid URL components")
        }

        var request = URLRequest(url: url)
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LBSError.networkError("Bad server response")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 429:
            throw LBSError.quotaExceeded
        default:
            throw LBSError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }
}
