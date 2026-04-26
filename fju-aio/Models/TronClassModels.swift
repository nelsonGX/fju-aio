import Foundation

// MARK: - Authentication Models

struct TronClassSession: Codable, Sendable {
    let sessionId: String
    let userId: Int
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

struct CASLoginResponse: Codable, Sendable {
    let user_id: Int
}

// MARK: - Authentication Errors

enum AuthenticationError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case invalidResponse
    case sessionExpired
    case tgtNotFound
    case serviceTicketInvalid
    case missingSessionId
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "帳號或密碼錯誤"
        case .networkError(let error): return "網路錯誤: \(error.localizedDescription)"
        case .invalidResponse: return "伺服器回應無效"
        case .sessionExpired: return "登入已過期，請重新登入"
        case .tgtNotFound: return "無法取得認證票證"
        case .serviceTicketInvalid: return "服務票證無效"
        case .missingSessionId: return "無法取得 Session ID"
        case .unknown: return "未知錯誤"
        }
    }
}
