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
        var components = URLComponents(string: baseURL + path)!
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
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
