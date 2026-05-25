import Foundation

/// 서울 열린데이터광장 API 에러
/// 응답 코드 (INFO-XXX, ERROR-XXX) 와 네트워크/디코딩 에러를 통합
enum SeoulAPIError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey            // INFO-100
    case noData                   // INFO-200
    case missingRequiredField     // ERROR-300
    case invalidFormat            // ERROR-301
    case serverError              // ERROR-500
    case dbError                  // ERROR-600 / 601
    case http(Int)
    case network(String)
    case decoding(Error)
    case unknown(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Seoul Open API 키가 설정되지 않았습니다"
        case .invalidAPIKey: return "API 키가 유효하지 않습니다 (INFO-100)"
        case .noData: return "데이터가 없습니다 (INFO-200)"
        case .missingRequiredField: return "필수 값이 누락되었습니다 (ERROR-300)"
        case .invalidFormat: return "파일 형식이 잘못되었습니다 (ERROR-301)"
        case .serverError: return "서버 오류 (ERROR-500)"
        case .dbError: return "DB 오류 (ERROR-600)"
        case .http(let code): return "HTTP \(code)"
        case .network(let msg): return "네트워크 오류: \(msg)"
        case .decoding(let err): return "디코딩 오류: \(err.localizedDescription)"
        case .unknown(let code, let msg): return "\(code): \(msg)"
        }
    }

    /// 서울 API 응답 결과 코드 → SeoulAPIError
    static func from(code: String, message: String) -> SeoulAPIError {
        switch code {
        case "INFO-000": return .unknown(code: code, message: message)  // 성공 코드 — 호출자가 분기 실수한 경우 방어
        case "INFO-100": return .invalidAPIKey
        case "INFO-200": return .noData
        case "ERROR-300": return .missingRequiredField
        case "ERROR-301": return .invalidFormat
        case "ERROR-500": return .serverError
        case "ERROR-600", "ERROR-601": return .dbError
        default: return .unknown(code: code, message: message)
        }
    }
}
