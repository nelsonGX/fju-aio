import Foundation
import os.log

@Observable
final class AuthenticationManager {
    private(set) var isAuthenticated = false
    private(set) var currentUserId: Int?
    private(set) var isLoading = false
    
    private let tronClassAuthService = TronClassAuthService.shared
    private let sisAuthService = SISAuthService.shared
    private let estuAuthService = EstuAuthService.shared
    private let fjuService = FJUService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "AuthManager")
    
    init() {
        Task {
            await checkInitialAuthState()
        }
    }
    
    @MainActor
    private func checkInitialAuthState() async {
        logger.info("🔍 Checking initial auth state...")
        let tronClassLoggedIn = await tronClassAuthService.isLoggedIn()
        let sisLoggedIn = await sisAuthService.isLoggedIn()
        isAuthenticated = tronClassLoggedIn || sisLoggedIn
        logger.info("Initial auth state: \(self.isAuthenticated ? "logged in" : "logged out")")
    }
    
    @MainActor
    func login(username: String, password: String) async throws {
        logger.info("🔐 Login attempt for: \(username)")
        isLoading = true
        
        // Update FJU service mode based on credentials
        fjuService.updateMode(username: username, password: password)
        
        // For demo/demo, skip actual authentication
        if username == "demo" && password == "demo" {
            logger.info("✅ Demo login successful (mock mode)")
            isAuthenticated = true
            currentUserId = 999999
            isLoading = false
            return
        }
        
        do {
            async let tronClassLogin = tronClassAuthService.login(username: username, password: password)
            async let sisLogin = sisAuthService.login(username: username, password: password)
            
            let (tronClassSession, sisSession) = try await (tronClassLogin, sisLogin)
            
            isAuthenticated = true
            currentUserId = sisSession.userId
            logger.info("✅ Login successful - TronClass User ID: \(tronClassSession.userId), SIS User ID: \(sisSession.userId)")
        } catch {
            logger.error("❌ Login failed: \(error.localizedDescription)")
            throw error
        }
        
        isLoading = false
    }
    
    @MainActor
    func logout() async throws {
        logger.info("👋 Logout initiated")
        isLoading = true
        defer { isLoading = false }
        
        do {
            await CourseNotificationManager.shared.cancelForLogout()
            try await tronClassAuthService.logout()
            try await sisAuthService.logout()
            try await estuAuthService.logout()
            AppCacheCleanupService.clearForLogout()
            isAuthenticated = false
            currentUserId = nil
            logger.info("✅ Logout successful")
        } catch {
            logger.error("❌ Logout failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getValidSession() async throws -> TronClassSession {
        return try await tronClassAuthService.getValidSession()
    }
    
    func getValidSISSession() async throws -> SISSession {
        return try await sisAuthService.getValidSession()
    }
}
