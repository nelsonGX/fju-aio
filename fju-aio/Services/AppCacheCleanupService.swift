import Foundation
import os.log
import WidgetKit

@MainActor
enum AppCacheCleanupService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "CacheCleanup")

    static func clearForLogout() async {
        await clearCloudKitData()
        await clearServiceCaches()
        FriendStore.shared.clearAll()
        AppCache.shared.invalidateAll()
        CertificateCache.shared.removeAll()
        PublicProfileCache.shared.clear()
        CourseNotificationManager.shared.resetLocalStateForLogout()
        URLCache.shared.removeAllCachedResponses()
        clearCookies()
        clearUserDefaults()
        clearKeychain()
        clearDirectoryContents(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        clearDirectoryContents(FileManager.default.temporaryDirectory)
        logger.info("✅ App caches cleared for logout")
    }

    private static func clearServiceCaches() async {
        await TronClassAPIService.shared.clearInMemoryCaches()
        await ClassroomScheduleService.shared.clearInMemoryCache()
    }

    private static func clearCloudKitData() async {
        await deleteFriendScheduleIfNeeded()
    }

    private static func deleteFriendScheduleIfNeeded() async {
        guard let token = ProfileQRService.existingScheduleShareToken() else { return }
        do {
            try await CloudKitProfileService.shared.deleteFriendSchedule(token: token)
        } catch {
            logger.error("Failed to delete CloudKit friend schedule during logout: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func clearCookies() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }
    }

    private static func clearUserDefaults() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        let widgetDefaults = WidgetDataStore.defaults
        widgetDefaults.removePersistentDomain(forName: WidgetDataStore.appGroupID)
        widgetDefaults.removeObject(forKey: WidgetDataStore.courseDataKey)
        widgetDefaults.removeObject(forKey: WidgetDataStore.assignmentDataKey)

        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func clearKeychain() {
        ProfileQRService.clearStoredTokens()
        do {
            try KeychainManager.shared.clearAll()
        } catch {
            logger.error("Failed to clear keychain during logout: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func clearDirectoryContents(_ directory: URL?) {
        guard let directory else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Failed to remove cache item \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
