import Foundation
import os.log

@MainActor
enum AppCacheCleanupService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fju.aio", category: "CacheCleanup")

    static func clearForLogout() {
        AppCache.shared.invalidateAll()
        CertificateCache.shared.removeAll()
        URLCache.shared.removeAllCachedResponses()
        clearCookies()
        clearDirectoryContents(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        clearDirectoryContents(FileManager.default.temporaryDirectory)
        logger.info("✅ App caches cleared for logout")
    }

    private static func clearCookies() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }
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
