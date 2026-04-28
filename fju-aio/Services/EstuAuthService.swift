import Foundation
import os.log

actor EstuAuthService {
    nonisolated static let shared = EstuAuthService()
    
    private let baseURL = "http://estu.fju.edu.tw"
    private let loginPath = "/CheckSelList/HisListNew.aspx"
    private let sessionKey = "com.fju.estu.session"
    private let credentialStore = CredentialStore.shared
    private let htmlParser = HTMLParser.shared
    
    /// Direct reference to cookie storage (URLSessionConfiguration is copied, so we keep our own ref)
    private let cookieStorage = HTTPCookieStorage.shared
    
    /// Dedicated URLSession using the shared cookie storage for ESTU requests
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Use the shared cookie storage so cookies persist and are accessible
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: config)
    }()
    
    private let logger = NetworkLogger.shared
    
    private var currentSession: EstuSession?
    
    private init() {
        Task { await loadSession() }
    }
    
    // MARK: - Public API
    
    func login(username: String, password: String) async throws -> EstuSession {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
        logger.info("🔐 Starting Estu login for user: \(username, privacy: .private)")
        
        do {
            logger.info("📝 Step 1: Fetching login page...")
            let viewState = try await fetchLoginPage()
            logger.info("✅ ViewState extracted")
            
            logger.info("📝 Step 2: Performing login...")
            let session = try await performLogin(username: username, password: password, viewState: viewState)
            logger.info("✅ Login successful")
            
            currentSession = session
            saveSession(session)
            
            return session
        } catch {
            logger.error("❌ Login failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    func getValidSession() async throws -> EstuSession {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
        logger.info("🔍 Checking for valid Estu session...")
        
        if let session = currentSession, !session.isExpired {
            logger.info("✅ Using cached session")
            return session
        }
        
        logger.info("⚠️ Session expired or missing, attempting refresh...")
        return try await forceRelogin()
    }
    
    /// Force a fresh login, clearing any cached session. Use when cookies are lost (e.g. app restart).
    func forceRelogin() async throws -> EstuSession {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
        logger.info("🔄 Force re-login...")
        
        currentSession = nil
        
        // Clear ESTU cookies to avoid stale session state before re-login
        if let url = URL(string: "\(baseURL)\(loginPath)") {
            let storage = HTTPCookieStorage.shared
            storage.cookies(for: url)?.forEach { storage.deleteCookie($0) }
        }
        
        guard let credentials = try? credentialStore.retrieveLDAPCredentials() else {
            logger.error("❌ No stored credentials found")
            throw EstuError.sessionExpired
        }
        
        return try await login(username: credentials.username, password: credentials.password)
    }
    
    func logout() throws {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
        logger.info("👋 Logging out from Estu...")
        currentSession = nil
        // Clear ESTU cookies from cookie storage
        if let url = URL(string: "\(baseURL)\(loginPath)") {
            cookieStorage.cookies(for: url)?.forEach { cookieStorage.deleteCookie($0) }
        }
        UserDefaults.standard.removeObject(forKey: sessionKey)
        logger.info("✅ Logout complete")
    }
    
    // MARK: - Private Methods
    
    private func fetchLoginPage() async throws -> EstuViewState {
        let url = URL(string: "\(baseURL)\(loginPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        
        logger.logRequest(request)
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EstuError.invalidResponse
        }
        logger.logResponse(httpResponse, data: data, error: nil)
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw EstuError.invalidResponse
        }
        
        return try htmlParser.extractViewState(from: html)
    }
    
    private func performLogin(username: String, password: String, viewState: EstuViewState) async throws -> EstuSession {
        let url = URL(string: "\(baseURL)\(loginPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("\(baseURL)\(loginPath)", forHTTPHeaderField: "Referer")
        
        let formData = [
            "__EVENTTARGET": "",
            "__EVENTARGUMENT": "",
            "__VIEWSTATE": viewState.viewState,
            "__VIEWSTATEGENERATOR": viewState.viewStateGenerator,
            "__EVENTVALIDATION": viewState.eventValidation,
            "TxtLdapId": username,
            "TxtLdapPwd": password,
            "ButLogin": "登入"
        ]
        
        request.httpBody = formData.percentEncoded()
        
        logger.logRequest(request)
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EstuError.invalidResponse
        }
        logger.logResponse(httpResponse, data: data, error: nil)
        
        guard httpResponse.statusCode == 200 else {
            throw EstuError.invalidResponse
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw EstuError.invalidResponse
        }
        
        if htmlParser.containsLoginError(in: html) {
            throw EstuError.invalidCredentials
        }
        
        // Extract session cookie from the response headers and cookie storage
        let headerFields = httpResponse.allHeaderFields as? [String: String] ?? [:]
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        let storageCookies = cookieStorage.cookies(for: url) ?? []
        let allCookies = responseCookies + storageCookies
        
        // Persist any Set-Cookie headers into the shared storage to ensure subsequent requests send them
        HTTPCookieStorage.shared.setCookies(responseCookies, for: url, mainDocumentURL: nil)
        
        guard let sessionCookie = allCookies.first(where: { $0.name == "ASP.NET_SessionId" }) else {
            throw EstuError.invalidResponse
        }
        
        let newViewState = try htmlParser.extractViewState(from: html)
        
        let expiresAt = Date().addingTimeInterval(20 * 60)
        
        return EstuSession(
            sessionId: sessionCookie.value,
            viewState: newViewState.viewState,
            viewStateGenerator: newViewState.viewStateGenerator,
            eventValidation: newViewState.eventValidation,
            expiresAt: expiresAt,
            loginResponseHTML: html
        )
    }
    
    // MARK: - Session Persistence
    
    private func saveSession(_ session: EstuSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
            logger.info("💾 Session saved")
        }
    }
    
    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(EstuSession.self, from: data),
              !session.isExpired else {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
            logger.info("⚠️ No valid session in storage")
            return
        }
        currentSession = session
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "EstuAuth")
        logger.info("✅ Session loaded from storage")
    }
    
    func getSessionCookies() -> [HTTPCookie] {
        guard let url = URL(string: "\(baseURL)\(loginPath)") else { return [] }
        return cookieStorage.cookies(for: url) ?? []
    }
    
    func getURLSession() -> URLSession {
        urlSession
    }
}

// MARK: - Dictionary Extension

private nonisolated extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        // Use a restricted character set for application/x-www-form-urlencoded
        // This must NOT include +, =, &, / which are significant in form encoding
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        
        return map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(escapedKey)=\(escapedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}
