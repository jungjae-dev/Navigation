import Foundation

enum LBSError: Error, LocalizedError, Equatable {
    case noRoutesFound
    case networkError(String)
    case cancelled
    case noResults
    case completionNotFound
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .noRoutesFound:
            return "경로를 찾을 수 없습니다"
        case .networkError(let message):
            return "네트워크 오류: \(message)"
        case .cancelled:
            return "요청이 취소되었습니다"
        case .noResults:
            return "결과를 찾을 수 없습니다"
        case .completionNotFound:
            return "검색 자동완성 항목을 찾을 수 없습니다"
        case .quotaExceeded:
            return "API 할당량이 초과되었습니다"
        }
    }
}
