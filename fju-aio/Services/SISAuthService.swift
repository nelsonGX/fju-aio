import Foundation
import os.log

actor SISAuthService {
    nonisolated static let shared = SISAuthService()
    
    private let baseURL = "https://travellerlink.fju.edu.tw"
    private let credentialStore = CredentialStore.shared
    private let networkService = NetworkService.shared
    private let sessionKey = "com.fju.sis.session"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "SISAuth")
    
    private var currentSession: SISSession?
    
    private init() {
        Task { await loadSession() }
    }
    
    // MARK: - Public API
    
    func login(username: String, password: String) async throws -> SISSession {
        logger.info("🔐 Starting SIS login for user: \(username, privacy: .private)")
        
        do {
            try credentialStore.saveLDAPCredentials(username: username, password: password)
            logger.info("✅ Credentials saved to keychain")
            
            logger.info("📝 Step 1: LDAP Login...")
            let loginResponse = try await performLDAPLogin(username: username, password: password)
            
            guard loginResponse.success,
                  let token = loginResponse.token else {
                logger.error("❌ Login failed: \(loginResponse.errorMessage.joined(separator: ", "), privacy: .public)")
                throw SISError.invalidCredentials
            }
            
            logger.info("✅ LDAP login successful")
            
            let (userId, userName) = try parseJWTToken(token)
            
            let expiresIn = loginResponse.result?.expires_in ?? 1200
            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            
            let session = SISSession(
                token: token,
                userId: userId,
                userName: userName,
                empNo: username,
                expiresAt: expiresAt
            )
            
            currentSession = session
            saveSession(session)
            logger.info("✅ SIS login complete!")
            
            return session
        } catch {
            logger.error("❌ Login failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    func getValidSession() async throws -> SISSession {
        logger.info("🔍 Checking for valid SIS session...")
        
        if let session = currentSession, !session.isExpired {
            logger.info("✅ Using cached session")
            return session
        }
        
        logger.info("⚠️ Session expired or missing, attempting refresh...")
        
        guard let credentials = try? credentialStore.retrieveLDAPCredentials() else {
            logger.error("❌ No stored credentials found")
            throw SISError.tokenExpired
        }
        
        logger.info("🔄 Refreshing session with stored credentials")
        return try await login(username: credentials.username, password: credentials.password)
    }
    
    func logout() async throws {
        logger.info("👋 Logging out from SIS...")
        currentSession = nil
        try credentialStore.deleteLDAPCredentials()
        UserDefaults.standard.removeObject(forKey: sessionKey)
        logger.info("✅ SIS logout complete")
    }
    
    func isLoggedIn() -> Bool {
        if let session = currentSession, !session.isExpired {
            logger.info("✅ User is logged in (valid session)")
            return true
        }
        let hasCredentials = credentialStore.hasLDAPCredentials()
        logger.info("🔍 Has stored credentials: \(hasCredentials, privacy: .public)")
        return hasCredentials
    }
    
    // MARK: - Private Methods
    
    private func performLDAPLogin(username: String, password: String) async throws -> LDAPLoginResponse {
        let url = URL(string: "\(baseURL)/FjuBase/api/Account/LdapLogin")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let loginRequest = LDAPLoginRequest(empNo: username, password: password)
        request.httpBody = try JSONEncoder().encode(loginRequest)
        
        do {
            let (data, httpResponse) = try await networkService.performRequest(request)
            
            if httpResponse.statusCode == 400 {
                logger.error("❌ Invalid credentials (400)")
                throw SISError.invalidCredentials
            }
            
            guard httpResponse.statusCode == 200 else {
                logger.error("❌ Unexpected status code: \(httpResponse.statusCode, privacy: .public)")
                throw SISError.invalidResponse
            }
            
            let response = try JSONDecoder().decode(LDAPLoginResponse.self, from: data)
            return response
        } catch let error as SISError {
            throw error
        } catch {
            throw SISError.networkError(error)
        }
    }
    
    private func parseJWTToken(_ token: String) throws -> (userId: Int, userName: String) {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            throw SISError.invalidResponse
        }
        
        var base64 = segments[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SISError.invalidResponse
        }
        
        let userIdString = json["sub"] as? String ?? ""
        let userName = json["CName"] as? String ?? "Unknown"
        let userId = Int(userIdString) ?? 0
        
        logger.info("📋 Parsed JWT - User ID: \(userId, privacy: .public), Name: \(userName, privacy: .private)")
        
        return (userId, userName)
    }
    
    // MARK: - Session Persistence
    
    private func saveSession(_ session: SISSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
            logger.info("💾 Session saved to UserDefaults")
        }
    }
    
    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(SISSession.self, from: data),
              !session.isExpired else {
            logger.info("⚠️ No valid session found in storage")
            return
        }
        currentSession = session
        logger.info("✅ Session loaded from storage")
    }
}
