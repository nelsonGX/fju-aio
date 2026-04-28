import Foundation

nonisolated struct EstuSession: Codable, Sendable {
    let sessionId: String // ASP.NET_SessionId
    let viewState: String
    let viewStateGenerator: String
    let eventValidation: String
    let expiresAt: Date
    /// The raw HTML from the login response (contains the authenticated course page).
    /// Not persisted — only available immediately after login.
    var loginResponseHTML: String?
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    enum CodingKeys: String, CodingKey {
        case sessionId, viewState, viewStateGenerator, eventValidation, expiresAt
    }
}

nonisolated struct EstuViewState: Sendable {
    let viewState: String
    let viewStateGenerator: String
    let eventValidation: String
}

nonisolated enum EstuError: LocalizedError {
    case invalidCredentials
    case sessionExpired
    case viewStateNotFound
    case parsingError
    case networkError(Error)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "帳號或密碼錯誤"
        case .sessionExpired: return "Session 已過期"
        case .viewStateNotFound: return "無法取得 ViewState"
        case .parsingError: return "解析 HTML 失敗"
        case .networkError(let error): return "網路錯誤: \(error.localizedDescription)"
        case .invalidResponse: return "伺服器回應無效"
        }
    }
}
