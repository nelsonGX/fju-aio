import Foundation
import os.log

@Observable
final class AuthenticationManager {
    private(set) var isAuthenticated = false
    private(set) var currentUserId: Int?
    private(set) var isLoading = false
    
    private let authService = TronClassAuthService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "AuthManager")
    
    init() {
        Task {
            await checkInitialAuthState()
        }
    }
    
    @MainActor
    private func checkInitialAuthState() async {
        logger.info("🔍 Checking initial auth state...")
        let loggedIn = await authService.isLoggedIn()
        isAuthenticated = loggedIn
        logger.info("Initial auth state: \(loggedIn ? "logged in" : "logged out")")
    }
    
    @MainActor
    func login(username: String, password: String) async throws {
        logger.info("🔐 Login attempt for: \(username)")
        isLoading = true
        
        do {
            let session = try await authService.login(username: username, password: password)
            isAuthenticated = true
            currentUserId = session.userId
            logger.info("✅ Login successful - User ID: \(session.userId)")
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
        
        do {
            try await authService.logout()
            isAuthenticated = false
            currentUserId = nil
            logger.info("✅ Logout successful")
        } catch {
            logger.error("❌ Logout failed: \(error.localizedDescription)")
            throw error
        }
        
        isLoading = false
    }
    
    func getValidSession() async throws -> TronClassSession {
        return try await authService.getValidSession()
    }
}
