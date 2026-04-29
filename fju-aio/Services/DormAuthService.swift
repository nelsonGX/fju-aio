import Foundation
import os.log

// MARK: - Models

nonisolated struct DormSession: Codable, Sendable {
    let token: String
    let userName: String
    let empNo: String
    let studentIdentity: String
    let roleSn: String
    let expiresAt: Date

    nonisolated var isExpired: Bool { Date() >= expiresAt }
}

// MARK: - Service

actor DormAuthService {
    nonisolated static let shared = DormAuthService()

    private let apiBase = "https://api-dorm.fju.edu.tw/api"
    private let credentialStore = CredentialStore.shared
    private let sessionKey = "com.fju.dorm.session"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "DormAuth")

    private var currentSession: DormSession?

    private init() {
        Task { await loadSession() }
    }

    // MARK: - Public API

    /// Returns a valid session, refreshing via stored credentials if needed.
    func getValidSession() async throws -> DormSession {
        if let session = currentSession, !session.isExpired {
            logger.info("✅ Using cached dorm session")
            return session
        }

        logger.info("⚠️ Dorm session expired or missing, refreshing...")

        guard let credentials = try? credentialStore.retrieveLDAPCredentials() else {
            logger.error("❌ No stored credentials for dorm login")
            throw DormAuthError.noCredentials
        }

        return try await login(username: credentials.username, password: credentials.password)
    }

    func login(username: String, password: String) async throws -> DormSession {
        logger.info("🔐 Dorm login for: \(username, privacy: .private)")

        let url = URL(string: "\(apiBase)/Account/LdapLogin")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://dorm.fju.edu.tw", forHTTPHeaderField: "Origin")
        request.setValue("https://dorm.fju.edu.tw/", forHTTPHeaderField: "Referer")

        let body: [String: String] = [
            "account": username,
            "password": password
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DormAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("❌ Dorm login HTTP \(httpResponse.statusCode)")
            throw DormAuthError.invalidCredentials
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["auth_token"] as? String, !token.isEmpty else {
            logger.error("❌ Dorm login: no auth_token in response")
            throw DormAuthError.invalidResponse
        }

        let payload = try parseJWT(token)
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(payload.exp))

        let session = DormSession(
            token: token,
            userName: payload.name,
            empNo: payload.empNo,
            studentIdentity: payload.studentIdentity,
            roleSn: payload.roleSn,
            expiresAt: expiresAt
        )

        currentSession = session
        saveSession(session)
        logger.info("✅ Dorm login successful, expires \(expiresAt)")
        return session
    }

    func clearSession() {
        currentSession = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
        logger.info("🗑️ Dorm session cleared")
    }

    // MARK: - JWT Parsing

    private struct JWTPayload {
        let name: String
        let empNo: String
        let studentIdentity: String
        let roleSn: String
        let exp: Int
    }

    private func parseJWT(_ token: String) throws -> JWTPayload {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else { throw DormAuthError.invalidResponse }

        var base64 = segments[1]
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DormAuthError.invalidResponse
        }

        return JWTPayload(
            name: json["Name"] as? String ?? "",
            empNo: json["EmpNo"] as? String ?? "",
            studentIdentity: json["StudentIdentity"] as? String ?? "S",
            roleSn: json["RoleSn"] as? String ?? "3",
            exp: json["exp"] as? Int ?? 0
        )
    }

    // MARK: - Session Persistence

    private func saveSession(_ session: DormSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(DormSession.self, from: data),
              !session.isExpired else { return }
        currentSession = session
        logger.info("✅ Dorm session loaded from storage")
    }
}

// MARK: - Errors

enum DormAuthError: LocalizedError {
    case noCredentials
    case invalidCredentials
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "無儲存的帳號密碼"
        case .invalidCredentials: return "帳號或密碼錯誤"
        case .invalidResponse: return "伺服器回應無效"
        }
    }
}
