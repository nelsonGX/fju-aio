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
    private var cloudSyncOwnerUserId: Int?
    private var cloudSyncTask: Task<Void, Never>?
    private var lastCloudSyncDataByUserId: [Int: Data] = [:]
    private var pendingCloudSyncDataByUserId: [Int: Data] = [:]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "FriendStore")
    private let friendsKey = "com.nelsongx.apps.fju-aio.friends"

    private init() { load() }

    // MARK: - Friends

    @discardableResult
    func addFriend(from payload: ProfileQRPayload) -> Bool {
        if let idx = friends.firstIndex(where: { $0.id == payload.cloudKitRecordName }) {
            friends[idx].displayName = payload.displayName
            if let token = payload.scheduleShareToken {
                friends[idx].scheduleShareToken = token
            }
            save()
            syncFriendsToCloud()
            logger.info("Friend \(payload.empNo) already in list")
            return false
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
        syncFriendsToCloud()
        logger.info("Added friend: \(payload.displayName) (\(payload.empNo))")
        return true
    }

    func isFriend(recordName: String) -> Bool {
        friends.contains { $0.id == recordName }
    }

    func updateCachedProfile(_ profile: PublicProfile, for id: String) {
        guard let idx = friends.firstIndex(where: { $0.id == id }) else { return }
        guard friends[idx].cachedProfile != profile || friends[idx].displayName != profile.displayName else { return }

        friends[idx].cachedProfile = profile
        friends[idx].displayName = profile.displayName
        save()
        syncFriendsToCloud()
        // Refresh widget with updated friend schedule data
        WidgetCenter.shared.reloadTimelines(ofKind: "CourseScheduleWidget")
    }

    func updateScheduleShareToken(_ token: String?, for id: String) {
        guard let token, let idx = friends.firstIndex(where: { $0.id == id }),
              friends[idx].scheduleShareToken != token else { return }
        friends[idx].scheduleShareToken = token
        save()
        syncFriendsToCloud()
    }

    func removeFriend(id: String) {
        if let record = friends.first(where: { $0.id == id }) {
            try? CredentialStore.shared.deleteFriendCredentials(empNo: record.empNo)
        }
        friends.removeAll { $0.id == id }
        save()
        syncFriendsToCloud()
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
        cloudSyncOwnerUserId = nil
        cloudSyncTask?.cancel()
        cloudSyncTask = nil
        lastCloudSyncDataByUserId.removeAll()
        pendingCloudSyncDataByUserId.removeAll()
        UserDefaults.standard.removeObject(forKey: friendsKey)
        logger.info("Cleared all friends and credentials")
    }

    func importCloudFriends(_ cloudFriends: [FriendRecord]) {
        guard !cloudFriends.isEmpty else { return }
        var mergedByID = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })

        for var cloudFriend in cloudFriends {
            cloudFriend.hasStoredCredentials = CredentialStore.shared.hasFriendCredentials(empNo: cloudFriend.empNo)
            if let existing = mergedByID[cloudFriend.id] {
                var merged = existing
                if cloudFriend.addedAt < existing.addedAt {
                    merged = cloudFriend
                    merged.hasStoredCredentials = existing.hasStoredCredentials || cloudFriend.hasStoredCredentials
                } else if let cloudProfile = cloudFriend.cachedProfile,
                          existing.cachedProfile == nil || cloudProfile.lastUpdated > existing.cachedProfile!.lastUpdated {
                    merged.cachedProfile = cloudProfile
                    merged.displayName = cloudProfile.displayName
                }
                if merged.scheduleShareToken == nil {
                    merged.scheduleShareToken = cloudFriend.scheduleShareToken
                }
                mergedByID[cloudFriend.id] = merged
            } else {
                mergedByID[cloudFriend.id] = cloudFriend
            }
        }

        friends = mergedByID.values.sorted { $0.addedAt < $1.addedAt }
        save()
        WidgetCenter.shared.reloadTimelines(ofKind: "CourseScheduleWidget")
        logger.info("Imported \(cloudFriends.count) friends from iCloud")
    }

    func setCloudSyncOwner(userId: Int) {
        cloudSyncOwnerUserId = userId
    }

    func syncFriendsToCloud() {
        guard iCloudAvailabilityService.shared.isPrivateDBAvailable else { return }
        guard let userId = cloudSyncOwnerUserId else { return }
        let snapshot = friends
        guard let data = encodedCloudSnapshot(snapshot),
              lastCloudSyncDataByUserId[userId] != data,
              pendingCloudSyncDataByUserId[userId] != data else { return }
        pendingCloudSyncDataByUserId[userId] = data

        cloudSyncTask?.cancel()
        cloudSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await CloudKitProfileIdentityService.shared.saveFriendRecords(snapshot, userId: userId)
                lastCloudSyncDataByUserId[userId] = data
                if pendingCloudSyncDataByUserId[userId] == data {
                    pendingCloudSyncDataByUserId[userId] = nil
                }
            } catch {
                await iCloudAvailabilityService.shared.handleCloudKitError(error)
                if pendingCloudSyncDataByUserId[userId] == data {
                    pendingCloudSyncDataByUserId[userId] = nil
                }
            }
        }
    }

    private func encodedCloudSnapshot(_ snapshot: [FriendRecord]) -> Data? {
        let sanitized = snapshot.map { friend in
            var copy = friend
            copy.hasStoredCredentials = false
            return copy
        }
        return try? JSONEncoder().encode(sanitized)
    }
}
