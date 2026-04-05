import Foundation

enum ChatServiceError: LocalizedError {
    case connectionFailed(String)
    case serverError(String)
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return msg
        case .serverError(let msg): return msg
        case .streamError(let msg): return msg
        }
    }
}
