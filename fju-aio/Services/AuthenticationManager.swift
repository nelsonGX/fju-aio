import Foundation
import os.log

@Observable
final class AuthenticationManager {
    private(set) var isAuthenticated = false
    private(set) var currentUserId: Int?
    private(set) var isLoading = false
    private(set) var isCheckingAuth = true
    private(set) var lastSignOutReason: String?
    
    private let tronClassAuthService = TronClassAuthService.shared
    private let sisAuthService = SISAuthService.shared
    private let estuAuthService = EstuAuthService.shared
    private let fjuService = FJUService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "AuthManager")
    
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
        await validateProfileIdentityIfNeeded()
        isCheckingAuth = false
        logger.info("Initial auth state: \(self.isAuthenticated ? "logged in" : "logged out")")
    }
    
    @MainActor
    func login(username: String, password: String) async throws {
        logger.info("🔐 Login attempt for: \(username)")
        isLoading = true
        defer { isLoading = false }
        
        // Update FJU service mode based on credentials
        fjuService.updateMode(username: username, password: password)
        
        // For demo/demo, skip actual authentication
        if username == "demo" && password == "demo" {
            logger.info("✅ Demo login successful (mock mode)")
            isAuthenticated = true
            currentUserId = 999999
            lastSignOutReason = nil
            return
        }
        
        do {
            async let tronClassLogin = tronClassAuthService.login(username: username, password: password)
            async let sisLogin = sisAuthService.login(username: username, password: password)
            
            let (tronClassSession, sisSession) = try await (tronClassLogin, sisLogin)

            do {
                try await CloudKitProfileIdentityService.shared.ensureIdentity(for: sisSession, allowTakeover: true)
                await importCloudFriends(userId: sisSession.userId)
            } catch {
                try? await tronClassAuthService.logout()
                try? await sisAuthService.logout()
                try? await estuAuthService.logout()
                await DormAuthService.shared.clearSession()
                await AppCacheCleanupService.clearForLogout()
                isAuthenticated = false
                currentUserId = nil
                throw error
            }

            isAuthenticated = true
            currentUserId = sisSession.userId
            lastSignOutReason = nil
            logger.info("✅ Login successful - TronClass User ID: \(tronClassSession.userId), SIS User ID: \(sisSession.userId)")
        } catch {
            logger.error("❌ Login failed: \(error.localizedDescription)")
            throw error
        }
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
            await DormAuthService.shared.clearSession()
            await AppCacheCleanupService.clearForLogout()
            isAuthenticated = false
            currentUserId = nil
            lastSignOutReason = nil
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

    @MainActor
    func clearLastSignOutReason() {
        lastSignOutReason = nil
    }

    @MainActor
    func validateProfileIdentityIfNeeded() async {
        guard isAuthenticated,
              let sisSession = try? await sisAuthService.getValidSession() else { return }

        do {
            try await CloudKitProfileIdentityService.shared.ensureIdentity(for: sisSession)
            await importCloudFriends(userId: sisSession.userId)
        } catch CloudKitProfileIdentityService.IdentityError.accountTakenOver {
            await forceLocalSignOut(reason: CloudKitProfileIdentityService.IdentityError.accountTakenOver.localizedDescription)
        } catch {
            logger.error("CloudKit identity validation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    @discardableResult
    func handleProfileIdentityError(_ error: Error) async -> Bool {
        guard let identityError = error as? CloudKitProfileIdentityService.IdentityError else {
            return false
        }

        switch identityError {
        case .accountTakenOver:
            await forceLocalSignOut(reason: identityError.localizedDescription)
            return true
        default:
            return false
        }
    }

    @MainActor
    private func forceLocalSignOut(reason: String) async {
        logger.warning("Signing out because account ownership moved to another iCloud account")
        await CourseNotificationManager.shared.cancelForLogout()
        try? await tronClassAuthService.logout()
        try? await sisAuthService.logout()
        try? await estuAuthService.logout()
        await DormAuthService.shared.clearSession()
        await AppCacheCleanupService.clearForLogout()
        isAuthenticated = false
        currentUserId = nil
        lastSignOutReason = reason
    }

    @MainActor
    private func importCloudFriends(userId: Int) async {
        FriendStore.shared.setCloudSyncOwner(userId: userId)
        guard let cloudFriends = try? await CloudKitProfileIdentityService.shared.fetchFriendRecords(userId: userId) else { return }
        FriendStore.shared.importCloudFriends(cloudFriends)
        FriendStore.shared.syncFriendsToCloud()
    }
}
