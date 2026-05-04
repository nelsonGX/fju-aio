import CloudKit
import Foundation
import os.log

// MARK: - iCloudSyncMode

/// Describes the current CloudKit operational state of the app.
enum iCloudSyncMode: Equatable {
    /// iCloud is signed in and has available storage — full sync enabled.
    case available

    /// iCloud is signed in but private DB storage quota is exceeded.
    /// The CloudKit PUBLIC database still works (it uses Apple's storage, not the user's quota).
    /// Public profile publishing and discovery work; friend list and private tokens are stored on-device.
    case quotaExceeded

    /// No iCloud account is signed in on this device.
    /// All CloudKit operations are unavailable; the device generates its own local identity.
    case noAccount

    /// iCloud access is restricted (e.g. parental controls, MDM).
    case restricted

    /// iCloud status could not be determined (transient).
    case couldNotDetermine

    // MARK: Computed helpers

    /// True when there is NO iCloud account at all — device-only identity is used.
    var isDeviceOnly: Bool {
        self == .noAccount || self == .restricted || self == .couldNotDetermine
    }

    /// True when private CloudKit DB writes are available (only full mode).
    var isPrivateDBAvailable: Bool {
        self == .available
    }

    /// True when the CloudKit public DB is accessible (full mode or quota-exceeded).
    /// The public DB uses Apple's shared storage and is unaffected by the user's personal quota.
    var isPublicDBAvailable: Bool {
        self == .available || self == .quotaExceeded
    }

    // MARK: User-facing strings (Traditional Chinese)

    /// Long description shown in Settings banner.
    var bannerDescription: String {
        switch self {
        case .available:
            return ""
        case .quotaExceeded:
            return "iCloud 儲存空間不足。好友清單與私鑰改為僅存於此裝置；公開資料與課表分享仍可正常運作。請至 iPhone 設定釋放 iCloud 空間後，點「重新檢查」可恢復完整同步。"
        case .noAccount:
            return "尚未登入 iCloud。好友、公開資料與行事曆同步功能已停用，資料僅存於此裝置。"
        case .restricted:
            return "iCloud 受限制（例如家庭監護）。好友同步功能已停用，資料僅存於此裝置。"
        case .couldNotDetermine:
            return "無法確認 iCloud 狀態。同步功能暫時停用。"
        }
    }

    /// Short inline label shown inside views.
    var shortLabel: String {
        switch self {
        case .available:
            return ""
        case .quotaExceeded:
            return "iCloud 空間不足 · 好友僅存於裝置"
        case .noAccount:
            return "未登入 iCloud · 資料僅存於裝置"
        case .restricted:
            return "iCloud 受限 · 資料僅存於裝置"
        case .couldNotDetermine:
            return "iCloud 暫時無法使用"
        }
    }

    /// SF Symbol name for the banner icon.
    var iconName: String {
        switch self {
        case .available:
            return "icloud.fill"
        case .quotaExceeded:
            return "externaldrive.badge.exclamationmark"
        case .noAccount, .restricted, .couldNotDetermine:
            return "icloud.slash"
        }
    }
}

// MARK: - iCloudAvailabilityService

/// Central tracker for CloudKit availability.
/// Observed by views via `@Environment(iCloudAvailabilityService.self)`.
/// Call `refresh()` at app launch and on every scene foreground.
@Observable
final class iCloudAvailabilityService {
    static let shared = iCloudAvailabilityService()

    private(set) var syncMode: iCloudSyncMode = .available

    // Convenience shorthands used throughout the codebase
    var isDeviceOnly: Bool { syncMode.isDeviceOnly }
    var isPrivateDBAvailable: Bool { syncMode.isPrivateDBAvailable }
    var isPublicDBAvailable: Bool { syncMode.isPublicDBAvailable }

    private let container = CKContainer(identifier: "iCloud.com.nelsongx.apps.fju-aio")
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio",
        category: "iCloudAvailability"
    )

    private init() {}

    // MARK: - Public API

    /// Checks the current iCloud account status and updates `syncMode`.
    /// Call this at app launch and whenever the scene becomes active.
    @MainActor
    func refresh() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                // Account is signed in. If quota was previously set by a failed write,
                // keep it — the user must explicitly retry via reset() to re-check.
                if syncMode == .quotaExceeded { return }
                setSyncMode(.available)
            case .noAccount:
                setSyncMode(.noAccount)
            case .restricted:
                setSyncMode(.restricted)
            case .couldNotDetermine, .temporarilyUnavailable:
                // Don't downgrade from a known state on a transient error
                if syncMode == .available { setSyncMode(.couldNotDetermine) }
            @unknown default:
                if syncMode == .available { setSyncMode(.couldNotDetermine) }
            }
        } catch {
            logger.error("accountStatus check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Call whenever a CloudKit operation fails.
    /// Returns true if the error triggered a mode change.
    @MainActor
    @discardableResult
    func handleCloudKitError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }

        if ckError.code == .notAuthenticated {
            // No iCloud account
            if syncMode != .noAccount {
                setSyncMode(.noAccount)
                return true
            }
        }

        if ckError.code == .quotaExceeded {
            if syncMode != .quotaExceeded {
                setSyncMode(.quotaExceeded)
                return true
            }
        }

        // Check nested partial errors
        if ckError.code == .partialFailure,
           let partialErrors = ckError.partialErrorsByItemID?.values {
            for partial in partialErrors {
                let code = (partial as? CKError)?.code
                if code == .quotaExceeded {
                    if syncMode != .quotaExceeded { setSyncMode(.quotaExceeded); return true }
                }
                if code == .notAuthenticated {
                    if syncMode != .noAccount { setSyncMode(.noAccount); return true }
                }
            }
        }

        return false
    }

    /// Clears device-only / quota state and re-checks iCloud availability.
    /// Call after the user has freed storage or signed in to iCloud.
    @MainActor
    func reset() async {
        syncMode = .available
        await refresh()
    }

    // MARK: - Internals

    @MainActor
    private func setSyncMode(_ mode: iCloudSyncMode) {
        guard syncMode != mode else { return }
        syncMode = mode
        if mode != .available {
            logger.warning("iCloud sync mode → \(mode.shortLabel, privacy: .public)")
        } else {
            logger.info("iCloud sync mode → available")
        }
    }
}
