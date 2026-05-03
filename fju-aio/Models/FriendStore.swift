import Foundation
import os.log
import WidgetKit

// MARK: - FriendStore
// Friend list persisted in UserDefaults (public profile data only).
// LDAP credentials are stored separately in Keychain via CredentialStore,
// keyed by empNo. hasStoredCredentials is recomputed from Keychain on load.

@Observable
@MainActor
final class FriendStore {
    static let shared = FriendStore()

    private(set) var friends: [FriendRecord] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "FriendStore")
    private let friendsKey = "com.nelsongx.apps.fju-aio.friends"

    private init() { load() }

    // MARK: - Friends

    func addFriend(from payload: ProfileQRPayload) {
        if let idx = friends.firstIndex(where: { $0.id == payload.cloudKitRecordName }) {
            if let token = payload.scheduleShareToken, friends[idx].scheduleShareToken != token {
                friends[idx].scheduleShareToken = token
                save()
            }
            logger.info("Friend \(payload.empNo) already in list")
            return
        }
        var record = FriendRecord(
            id: payload.cloudKitRecordName,
            empNo: payload.empNo,
            displayName: payload.displayName,
            cachedProfile: nil,
            scheduleShareToken: payload.scheduleShareToken,
            addedAt: Date()
        )
        record.hasStoredCredentials = CredentialStore.shared.hasFriendCredentials(empNo: payload.empNo)
        friends.append(record)
        save()
        logger.info("Added friend: \(payload.displayName) (\(payload.empNo))")
    }

    func isFriend(recordName: String) -> Bool {
        friends.contains { $0.id == recordName }
    }

    func updateCachedProfile(_ profile: PublicProfile, for id: String) {
        guard let idx = friends.firstIndex(where: { $0.id == id }) else { return }
        friends[idx].cachedProfile = profile
        friends[idx].displayName = profile.displayName
        save()
        // Refresh widget with updated friend schedule data
        WidgetCenter.shared.reloadTimelines(ofKind: "CourseScheduleWidget")
    }

    func updateScheduleShareToken(_ token: String?, for id: String) {
        guard let token, let idx = friends.firstIndex(where: { $0.id == id }),
              friends[idx].scheduleShareToken != token else { return }
        friends[idx].scheduleShareToken = token
        save()
    }

    func removeFriend(id: String) {
        if let record = friends.first(where: { $0.id == id }) {
            try? CredentialStore.shared.deleteFriendCredentials(empNo: record.empNo)
        }
        friends.removeAll { $0.id == id }
        save()
        WidgetCenter.shared.reloadTimelines(ofKind: "CourseScheduleWidget")
        logger.info("Removed friend \(id)")
    }

    // MARK: - Credential Management

    func saveCredentials(for friendId: String, username: String, password: String) {
        guard let idx = friends.firstIndex(where: { $0.id == friendId }) else { return }
        do {
            try CredentialStore.shared.saveFriendCredentials(
                empNo: friends[idx].empNo,
                username: username,
                password: password
            )
            friends[idx].hasStoredCredentials = true
            logger.info("Saved credentials for \(self.friends[idx].displayName)")
        } catch {
            logger.error("Failed to save credentials: \(error)")
        }
    }

    func deleteCredentials(for friendId: String) {
        guard let idx = friends.firstIndex(where: { $0.id == friendId }) else { return }
        try? CredentialStore.shared.deleteFriendCredentials(empNo: friends[idx].empNo)
        friends[idx].hasStoredCredentials = false
        logger.info("Deleted credentials for \(self.friends[idx].displayName)")
    }

    /// All friends who have stored credentials — used by CheckInView
    var credentialedFriends: [FriendRecord] {
        friends.filter { $0.hasStoredCredentials }
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: friendsKey),
           var decoded = try? JSONDecoder().decode([FriendRecord].self, from: data) {
            // Recompute hasStoredCredentials from Keychain (not persisted in JSON)
            for i in decoded.indices {
                decoded[i].hasStoredCredentials = CredentialStore.shared.hasFriendCredentials(empNo: decoded[i].empNo)
            }
            friends = decoded
        }
        logger.info("Loaded \(self.friends.count) friends")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: friendsKey)
        }
    }

    func clearAll() {
        for friend in friends {
            try? CredentialStore.shared.deleteFriendCredentials(empNo: friend.empNo)
        }
        friends = []
        UserDefaults.standard.removeObject(forKey: friendsKey)
        logger.info("Cleared all friends and credentials")
    }
}
