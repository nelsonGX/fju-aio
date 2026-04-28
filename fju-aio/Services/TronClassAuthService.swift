import Foundation
import os.log

actor TronClassAuthService {
    nonisolated static let shared = TronClassAuthService()
    
    private let baseURL = "https://elearn2.fju.edu.tw"
    private let credentialStore = CredentialStore.shared
    private let networkService = NetworkService.shared
    private let sessionKey = "com.fju.tronclass.session"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "Auth")
    
    private var currentSession: TronClassSession?
    
    private init() {
        Task { await loadSession() }
    }
    
    // MARK: - Public API
    
    func login(username: String, password: String) async throws -> TronClassSession {
        logger.info("🔐 Starting login for user: \(username, privacy: .private)")
        
        do {
            // Save credentials
            try credentialStore.saveLDAPCredentials(username: username, password: password)
            logger.info("✅ Credentials saved to keychain")
            
            // Step 1: Get TGT
            logger.info("📝 Step 1: Fetching TGT...")
            let tgt = try await fetchTGT(username: username, password: password)
            logger.info("✅ TGT received: \(tgt.prefix(20), privacy: .private)...")
            
            // Step 2: Get Service Ticket
            logger.info("📝 Step 2: Fetching Service Ticket...")
            let serviceTicket = try await fetchServiceTicket(tgt: tgt)
            logger.info("✅ Service Ticket received: \(serviceTicket.prefix(20), privacy: .private)...")
            
            // Step 3: Exchange for Session
            logger.info("📝 Step 3: Exchanging for Session...")
            let session = try await exchangeForSession(serviceTicket: serviceTicket)
            logger.info("✅ Session created - User ID: \(session.userId, privacy: .public), Expires: \(session.expiresAt, privacy: .public)")
            
            // Store session
            currentSession = session
            saveSession(session)
            logger.info("✅ Login complete!")
            
            return session
        } catch {
            logger.error("❌ Login failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    func getValidSession() async throws -> TronClassSession {
        logger.info("🔍 Checking for valid session...")
        
        // Check if we have a valid session
        if let session = currentSession, !session.isExpired {
            logger.info("✅ Using cached session")
            return session
        }
        
        logger.info("⚠️ Session expired or missing, attempting refresh...")
        
        // Try to refresh with stored credentials
        guard let credentials = try? credentialStore.retrieveLDAPCredentials() else {
            logger.error("❌ No stored credentials found")
            throw AuthenticationError.sessionExpired
        }
        
        logger.info("🔄 Refreshing session with stored credentials")
        return try await login(username: credentials.username, password: credentials.password)
    }
    
    func logout() async throws {
        logger.info("👋 Logging out...")
        currentSession = nil
        try credentialStore.deleteLDAPCredentials()
        UserDefaults.standard.removeObject(forKey: sessionKey)
        logger.info("✅ Logout complete")
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
    
    // MARK: - CAS Authentication Flow
    
    private func fetchTGT(username: String, password: String) async throws -> String {
        let url = URL(string: "\(baseURL)/cas/v1/tickets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("TronClass/2.14.5 (iPhone; iOS 18.2; Scale/3.00)", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-Hant-TW;q=1, en-TW;q=0.9, zh-Hans-TW;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&password=\(password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (_, httpResponse) = try await networkService.performRequest(request)
            
            if httpResponse.statusCode == 400 {
                logger.error("❌ Invalid credentials (400)")
                throw AuthenticationError.invalidCredentials
            }
            
            guard httpResponse.statusCode == 201,
                  let location = httpResponse.value(forHTTPHeaderField: "Location"),
                  let tgt = location.components(separatedBy: "/").last else {
                logger.error("❌ TGT not found in response")
                throw AuthenticationError.tgtNotFound
            }
            
            return tgt
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.networkError(error)
        }
    }
    
    private func fetchServiceTicket(tgt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/cas/v1/tickets/\(tgt)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("TronClass/2.14.5 (iPhone; iOS 18.2; Scale/3.00)", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-Hant-TW;q=1, en-TW;q=0.9, zh-Hans-TW;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "service=https://elearn2.fju.edu.tw/api/cas-login"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, httpResponse) = try await networkService.performRequest(request)
            
            if httpResponse.statusCode == 404 {
                logger.error("❌ TGT invalid or expired (404)")
                throw AuthenticationError.tgtNotFound
            }
            
            guard httpResponse.statusCode == 200,
                  let serviceTicket = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                logger.error("❌ Service ticket invalid")
                throw AuthenticationError.serviceTicketInvalid
            }
            
            return serviceTicket
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.networkError(error)
        }
    }
    
    private func exchangeForSession(serviceTicket: String) async throws -> TronClassSession {
        var components = URLComponents(string: "\(baseURL)/api/cas-login")!
        components.queryItems = [URLQueryItem(name: "ticket", value: serviceTicket)]
        
        guard let url = components.url else {
            throw AuthenticationError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("capacitor://localhost", forHTTPHeaderField: "Origin")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TronClass/common", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh-Hant;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        
        do {
            let (data, httpResponse) = try await networkService.performRequest(request)
            
            if httpResponse.statusCode == 401 {
                logger.error("❌ Service ticket invalid (401)")
                throw AuthenticationError.serviceTicketInvalid
            }
            
            guard httpResponse.statusCode == 200 else {
                logger.error("❌ Unexpected status code: \(httpResponse.statusCode, privacy: .public)")
                throw AuthenticationError.invalidResponse
            }
            
            guard let sessionId = httpResponse.value(forHTTPHeaderField: "X-SESSION-ID") else {
                logger.error("❌ X-SESSION-ID header missing")
                throw AuthenticationError.missingSessionId
            }
            
            let loginResponse = try JSONDecoder().decode(CASLoginResponse.self, from: data)
            
            // Parse expiration time from session ID
            // Format: V2-1-{uuid}.{base64}.{timestamp}.{signature}
            let expiresAt = parseExpirationFromSessionId(sessionId)
            logger.info("📅 Session expires at: \(expiresAt, privacy: .public)")
            
            return TronClassSession(
                sessionId: sessionId,
                userId: loginResponse.user_id,
                expiresAt: expiresAt
            )
        } catch let error as AuthenticationError {
            throw error
        } catch {
            logger.error("❌ Decoding error: \(error.localizedDescription, privacy: .public)")
            throw AuthenticationError.networkError(error)
        }
    }
    
    // MARK: - Session Parsing
    
    private func parseExpirationFromSessionId(_ sessionId: String) -> Date {
        // Session ID format: V2-1-{uuid}.{base64}.{timestamp}.{signature}
        let components = sessionId.components(separatedBy: ".")
        
        guard components.count >= 3,
              let timestampString = components[safe: 2],
              let timestamp = TimeInterval(timestampString) else {
            logger.warning("⚠️ Could not parse expiration from session ID, using default 24h")
            return Date().addingTimeInterval(24 * 60 * 60)
        }
        
        // Timestamp is in milliseconds
        let expirationDate = Date(timeIntervalSince1970: timestamp / 1000)
        return expirationDate
    }
    
    // MARK: - Session Persistence
    
    private func saveSession(_ session: TronClassSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
            logger.info("💾 Session saved to UserDefaults")
        }
    }
    
    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(TronClassSession.self, from: data),
              !session.isExpired else {
            logger.info("⚠️ No valid session found in storage")
            return
        }
        currentSession = session
        logger.info("✅ Session loaded from storage")
    }
}

// MARK: - Array Safe Subscript

private nonisolated extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
