import Foundation
import Observation

/// App-wide sync status tracker. Any view or service can call `begin`/`end`
/// (or the convenience `withSync`) to post a named operation. The banner in
/// ContentView shows while at least one operation is in flight.
@Observable
@MainActor
final class SyncStatusManager {
    static let shared = SyncStatusManager()

    private init() {}

    /// Whether the sync banner is enabled. Persisted across launches.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "syncStatusBannerEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "syncStatusBannerEnabled")
            if !newValue { activeCount = 0 }
        }
    }

    /// Human-readable label for the most recently started operation.
    private(set) var message: String = ""

    /// True whenever at least one operation is in flight and the banner is enabled.
    var isSyncing: Bool { isEnabled && activeCount > 0 }

    private var activeCount: Int = 0

    /// Begin a named operation. Must be balanced by a call to `end()`.
    func begin(_ message: String) {
        guard isEnabled else { return }
        activeCount += 1
        self.message = message
    }

    /// Mark one operation as finished.
    func end() {
        activeCount = max(0, activeCount - 1)
    }

    /// Convenience wrapper: runs `work` on the main actor, bracketing it with begin/end.
    func withSync<T>(_ message: String, work: @MainActor () async throws -> T) async rethrows -> T {
        begin(message)
        defer { end() }
        return try await work()
    }
}
