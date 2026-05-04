import CloudKit
import CryptoKit
import Foundation
import os.log

nonisolated enum ProfileIdentity {
    static func publicRecordName(userId: Int) -> String {
        "user-\(userId)"
    }

    static func publicRecordName(for session: SISSession) -> String {
        publicRecordName(userId: session.userId)
    }

    static func accountBindingRecordName(userId: Int) -> String {
        "account-\(userId)"
    }

    static func publicRecordName(userId: Int, bindingKey: String) -> String {
        let ownerSuffix = String(bindingKey.prefix(16))
        return "profile-\(userId)-\(ownerSuffix)"
    }

    static func userIdFromAliasRecordName(_ recordName: String) -> Int? {
        guard recordName.hasPrefix("user-") else { return nil }
        return Int(recordName.dropFirst("user-".count))
    }
}

actor CloudKitProfileIdentityService {
    static let shared = CloudKitProfileIdentityService()

    private let container = CKContainer(identifier: "iCloud.com.nelsongx.apps.fju-aio")
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "CloudKitIdentity")
    private let ensuredIdentityCacheTTL: TimeInterval = 10 * 60
    private var ensuredIdentityCache: [Int: EnsuredIdentityCacheEntry] = [:]

    private init() {}

    private struct EnsuredIdentityCacheEntry {
        let publicRecordName: String
        let empNo: String
        let iCloudBindingKey: String
        let cachedAt: Date
    }

    enum IdentityError: LocalizedError {
        case iCloudUnavailable
        case accountTakenOver
        case missingSaveResult(recordName: String)

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "請先登入 iCloud，才能同步公開個人檔案與好友資料。"
            case .accountTakenOver:
                return "你的帳號好像在其他不屬於你的裝置上登入了。我們將登出這裡的帳號，如果你認為這不太對，請盡快更改 LDAP 密碼後重新在這裡登入。"
            case .missingSaveResult(let recordName):
                return "CloudKit did not return a save result for recordName=\(recordName)"
            }
        }
    }

    private enum PrivateIdentityField {
        static let recordType = "UserProfileIdentity"
        static let legacyRecordName = "current"
        static let ownerUserId = "ownerUserId"
        static let empNo = "empNo"
        static let activePublicRecordName = "activePublicRecordName"
        static let boundICloudUserID = "boundICloudUserID"
        static let scheduleShareToken = "scheduleShareToken"
        static let lastUpdated = "lastUpdated"
        static let deviceId = "deviceId"
    }

    private enum PublicBindingField {
        static let recordType = "AccountProfileBindingClaim"
        static let ownerUserId = "ownerUserId"
        static let empNo = "empNo"
        static let activePublicRecordName = "activePublicRecordName"
        static let boundICloudUserID = "boundICloudUserID"
        static let lastUpdated = "lastUpdated"
    }

    private enum FriendListField {
        static let recordType = "PrivateFriendList"
        static let legacyRecordName = "current"
        static let friendsData = "friendsData"
        static let lastUpdated = "lastUpdated"
    }

    @discardableResult
    func ensureIdentity(
        for session: SISSession,
        allowTakeover: Bool = false,
        forceRefresh: Bool = false
    ) async throws -> String {
        let availability = iCloudAvailabilityService.shared

        // MARK: No-Account path — device-local identity
        // When there is no iCloud account at all, we cannot use any CloudKit database.
        // Generate a stable record name anchored to this device via a Keychain-stored key.
        if availability.isDeviceOnly {
            return deviceOnlyIdentity(for: session)
        }

        // MARK: Quota-Exceeded path — real iCloud identity, public DB only
        // The user IS signed in to iCloud but their private storage is full.
        // CloudKit PUBLIC database writes don't count against the user's personal quota,
        // so public profile publishing and binding still work.
        // We skip the private DB write (ensurePrivateIdentity) and store tokens locally.
        if availability.syncMode == .quotaExceeded {
            return try await quotaExceededIdentity(for: session, allowTakeover: allowTakeover, forceRefresh: forceRefresh)
        }

        // MARK: Full-Available path
        let iCloudUserID: String
        do {
            iCloudUserID = try await currentICloudUserID()
        } catch {
            await availability.handleCloudKitError(error)
            // Mode may have changed — recurse once to apply the correct path
            return try await ensureIdentity(for: session, allowTakeover: allowTakeover, forceRefresh: forceRefresh)
        }

        let iCloudBindingKey = bindingKey(for: iCloudUserID)
        let publicRecordName = ProfileIdentity.publicRecordName(userId: session.userId, bindingKey: iCloudBindingKey)

        if !allowTakeover,
           !forceRefresh,
           let cached = ensuredIdentityCache[session.userId],
           cached.publicRecordName == publicRecordName,
           cached.empNo == session.empNo,
           cached.iCloudBindingKey == iCloudBindingKey,
           Date().timeIntervalSince(cached.cachedAt) < ensuredIdentityCacheTTL {
            return cached.publicRecordName
        }

        do {
            try await ensurePublicBinding(
                session: session,
                publicRecordName: publicRecordName,
                iCloudBindingKey: iCloudBindingKey,
                allowTakeover: allowTakeover
            )
            try await ensurePrivateIdentity(
                session: session,
                publicRecordName: publicRecordName,
                iCloudBindingKey: iCloudBindingKey
            )
        } catch {
            await availability.handleCloudKitError(error)
            if case .accountTakenOver = error as? IdentityError { throw error }
            // Mode changed (e.g. quota just exceeded) — recurse to apply correct path
            if availability.syncMode != .available {
                return try await ensureIdentity(for: session, allowTakeover: allowTakeover, forceRefresh: false)
            }
            logger.warning("⚠️ Binding write failed: \(error.localizedDescription, privacy: .public)")
        }

        ensuredIdentityCache[session.userId] = EnsuredIdentityCacheEntry(
            publicRecordName: publicRecordName,
            empNo: session.empNo,
            iCloudBindingKey: iCloudBindingKey,
            cachedAt: Date()
        )
        return publicRecordName
    }

    /// Device-local identity: no iCloud account, Keychain-stored binding key.
    private func deviceOnlyIdentity(for session: SISSession) -> String {
        let local = deviceLocalPublicRecordName(for: session.userId)
        logger.info("ℹ️ No-account identity: \(local, privacy: .private)")
        ensuredIdentityCache[session.userId] = EnsuredIdentityCacheEntry(
            publicRecordName: local,
            empNo: session.empNo,
            iCloudBindingKey: "device",
            cachedAt: Date()
        )
        _ = ProfileQRService.scheduleShareToken()
        return local
    }

    /// Quota-exceeded identity: real iCloud binding key, public DB only.
    private func quotaExceededIdentity(
        for session: SISSession,
        allowTakeover: Bool,
        forceRefresh: Bool
    ) async throws -> String {
        let iCloudUserID = try await currentICloudUserID()
        let iCloudBindingKey = bindingKey(for: iCloudUserID)
        let publicRecordName = ProfileIdentity.publicRecordName(userId: session.userId, bindingKey: iCloudBindingKey)

        if !forceRefresh,
           let cached = ensuredIdentityCache[session.userId],
           cached.publicRecordName == publicRecordName,
           cached.empNo == session.empNo,
           Date().timeIntervalSince(cached.cachedAt) < ensuredIdentityCacheTTL {
            return cached.publicRecordName
        }

        // Public DB binding still works (unaffected by user's personal storage quota)
        do {
            try await ensurePublicBinding(
                session: session,
                publicRecordName: publicRecordName,
                iCloudBindingKey: iCloudBindingKey,
                allowTakeover: allowTakeover
            )
        } catch {
            if case .accountTakenOver = error as? IdentityError { throw error }
            logger.warning("⚠️ Quota mode: public binding failed: \(error.localizedDescription, privacy: .public)")
        }

        // Private DB write is skipped — store schedule token locally instead
        _ = ProfileQRService.scheduleShareToken()
        logger.info("ℹ️ Quota mode: private DB write skipped, using computed record name")

        ensuredIdentityCache[session.userId] = EnsuredIdentityCacheEntry(
            publicRecordName: publicRecordName,
            empNo: session.empNo,
            iCloudBindingKey: iCloudBindingKey,
            cachedAt: Date()
        )
        return publicRecordName
    }

    func activePublicRecordName(userId: Int) async throws -> String? {
        let claim = try await latestPublicBindingClaim(userId: userId)
        if let claim {
            return claim.activePublicRecordName
        }

        let legacy = try await legacyPublicBinding(userId: userId)
        return legacy?.activePublicRecordName ?? ProfileIdentity.publicRecordName(userId: userId)
    }

    func deletePublicBinding(for session: SISSession) async throws {
        let recordID = CKRecord.ID(recordName: ProfileIdentity.accountBindingRecordName(userId: session.userId))
        do {
            _ = try await publicDB.modifyRecords(saving: [], deleting: [recordID])
        } catch let error as CKError where isMissingRecordError(error) {
            return
        }
    }

    func deletePrivateIdentity(userId: Int) async throws {
        let recordID = CKRecord.ID(recordName: privateIdentityRecordName(userId: userId))
        do {
            _ = try await privateDB.modifyRecords(saving: [], deleting: [recordID])
        } catch let error as CKError where isMissingRecordError(error) {
            return
        }
    }

    func fetchFriendRecords(userId: Int) async throws -> [FriendRecord] {
        let availability = iCloudAvailabilityService.shared
        // No account: local FriendStore (UserDefaults) is authoritative, return nothing to merge.
        if availability.isDeviceOnly { return [] }
        // Quota exceeded: private DB reads usually still work — try and fall back gracefully.
        let recordID = CKRecord.ID(recordName: friendListRecordName(userId: userId))
        do {
            let record = try await privateDB.record(for: recordID)
            return decodeFriendRecords(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return try await fetchLegacyFriendRecords()
        } catch let error as CKError where error.code == .quotaExceeded || error.code == .notAuthenticated {
            await availability.handleCloudKitError(error)
            return []
        }
    }

    func saveFriendRecords(_ friends: [FriendRecord], userId: Int) async throws {
        // Private DB writes require available personal iCloud storage.
        // In quota-exceeded or no-account modes, FriendStore (UserDefaults) is authoritative.
        guard iCloudAvailabilityService.shared.isPrivateDBAvailable else { return }
        let recordID = CKRecord.ID(recordName: friendListRecordName(userId: userId))
        let record = try await privateFriendListRecord(recordID: recordID)
        let sanitized = friends.map { friend in
            var copy = friend
            copy.hasStoredCredentials = false
            return copy
        }
        record[FriendListField.friendsData] = try JSONEncoder().encode(sanitized) as CKRecordValue
        record[FriendListField.lastUpdated] = Date() as CKRecordValue
        try await save(record, in: privateDB)
    }

    private func currentICloudUserID() async throws -> String {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw IdentityError.iCloudUnavailable
        }
        return try await container.userRecordID().recordName
    }

    private func ensurePrivateIdentity(
        session: SISSession,
        publicRecordName: String,
        iCloudBindingKey: String
    ) async throws {
        let recordID = CKRecord.ID(recordName: privateIdentityRecordName(userId: session.userId))
        let record = try await privateIdentityRecord(recordID: recordID)

        if let boundICloudUserID = record[PrivateIdentityField.boundICloudUserID] as? String,
           boundICloudUserID != iCloudBindingKey {
            throw IdentityError.accountTakenOver
        }

        let scheduleShareToken: String
        if let remoteToken = record[PrivateIdentityField.scheduleShareToken] as? String,
           !remoteToken.isEmpty {
            scheduleShareToken = remoteToken
            ProfileQRService.storeScheduleShareToken(remoteToken)
        } else {
            scheduleShareToken = ProfileQRService.scheduleShareToken()
        }

        record[PrivateIdentityField.ownerUserId] = session.userId as CKRecordValue
        record[PrivateIdentityField.empNo] = session.empNo as CKRecordValue
        record[PrivateIdentityField.activePublicRecordName] = publicRecordName as CKRecordValue
        record[PrivateIdentityField.boundICloudUserID] = iCloudBindingKey as CKRecordValue
        record[PrivateIdentityField.scheduleShareToken] = scheduleShareToken as CKRecordValue
        record[PrivateIdentityField.lastUpdated] = Date() as CKRecordValue
        record[PrivateIdentityField.deviceId] = ProfileQRService.stableDeviceToken() as CKRecordValue

        try await save(record, in: privateDB)
    }

    private func ensurePublicBinding(
        session: SISSession,
        publicRecordName: String,
        iCloudBindingKey: String,
        allowTakeover: Bool
    ) async throws {
        let activeClaim = try await latestPublicBindingClaim(userId: session.userId)
        if let activeClaim,
           activeClaim.boundICloudUserID != iCloudBindingKey,
           !allowTakeover {
            throw IdentityError.accountTakenOver
        }
        if let legacy = try await legacyPublicBinding(userId: session.userId),
           legacy.boundICloudUserID != iCloudBindingKey,
           activeClaim == nil,
           !allowTakeover {
            throw IdentityError.accountTakenOver
        }

        let recordID = CKRecord.ID(recordName: publicBindingClaimRecordName(userId: session.userId, bindingKey: iCloudBindingKey))
        let record = try await publicBindingRecord(recordID: recordID)

        record[PublicBindingField.ownerUserId] = session.userId as CKRecordValue
        record[PublicBindingField.empNo] = session.empNo as CKRecordValue
        record[PublicBindingField.activePublicRecordName] = publicRecordName as CKRecordValue
        record[PublicBindingField.boundICloudUserID] = iCloudBindingKey as CKRecordValue
        record[PublicBindingField.lastUpdated] = Date() as CKRecordValue

        try await save(record, in: publicDB)
    }

    private struct PublicBindingClaim {
        let activePublicRecordName: String
        let boundICloudUserID: String
    }

    private func latestPublicBindingClaim(userId: Int) async throws -> PublicBindingClaim? {
        let query = CKQuery(
            recordType: PublicBindingField.recordType,
            predicate: NSPredicate(format: "%K == %d", PublicBindingField.ownerUserId, userId)
        )
        query.sortDescriptors = [NSSortDescriptor(key: PublicBindingField.lastUpdated, ascending: false)]

        do {
            let (matchResults, _) = try await publicDB.records(
                matching: query,
                desiredKeys: [
                    PublicBindingField.activePublicRecordName,
                    PublicBindingField.boundICloudUserID
                ],
                resultsLimit: 1
            )
            guard let result = matchResults.first?.1,
                  case .success(let record) = result else { return nil }
            return decodePublicBindingClaim(record)
        } catch let error as CKError where isMissingRecordError(error) {
            return nil
        }
    }

    private func legacyPublicBinding(userId: Int) async throws -> PublicBindingClaim? {
        let recordID = CKRecord.ID(recordName: ProfileIdentity.accountBindingRecordName(userId: userId))
        do {
            let record = try await publicDB.record(for: recordID)
            return decodePublicBindingClaim(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError where error.code == .permissionFailure {
            return nil
        }
    }

    private func decodePublicBindingClaim(_ record: CKRecord) -> PublicBindingClaim? {
        guard let activePublicRecordName = record[PublicBindingField.activePublicRecordName] as? String,
              let boundICloudUserID = record[PublicBindingField.boundICloudUserID] as? String else {
            return nil
        }
        return PublicBindingClaim(
            activePublicRecordName: activePublicRecordName,
            boundICloudUserID: boundICloudUserID
        )
    }

    private func publicBindingClaimRecordName(userId: Int, bindingKey: String) -> String {
        "claim-\(userId)-\(String(bindingKey.prefix(16)))"
    }

    private func privateIdentityRecordName(userId: Int) -> String {
        "identity-\(userId)"
    }

    private func friendListRecordName(userId: Int) -> String {
        "friends-\(userId)"
    }

    private func fetchLegacyFriendRecords() async throws -> [FriendRecord] {
        let legacyRecordID = CKRecord.ID(recordName: FriendListField.legacyRecordName)
        do {
            let record = try await privateDB.record(for: legacyRecordID)
            return decodeFriendRecords(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    private func decodeFriendRecords(from record: CKRecord) -> [FriendRecord] {
        guard let data = record[FriendListField.friendsData] as? Data else { return [] }
        return (try? JSONDecoder().decode([FriendRecord].self, from: data)) ?? []
    }

    private func privateIdentityRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await privateDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: PrivateIdentityField.recordType, recordID: recordID)
        }
    }

    private func publicBindingRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await publicDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: PublicBindingField.recordType, recordID: recordID)
        }
    }

    private func privateFriendListRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await privateDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: FriendListField.recordType, recordID: recordID)
        }
    }

    private func save(_ record: CKRecord, in database: CKDatabase) async throws {
        let saveResults = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        ).saveResults
        guard let saveResult = saveResults[record.recordID] else {
            throw IdentityError.missingSaveResult(recordName: record.recordID.recordName)
        }

        switch saveResult {
        case .success:
            logger.info("✅ Saved identity record \(record.recordID.recordName, privacy: .public)")
        case .failure(let error):
            throw error
        }
    }

    private func bindingKey(for iCloudUserID: String) -> String {
        let digest = SHA256.hash(data: Data("fju-aio-profile-identity:\(iCloudUserID)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func intValue(for key: String, in record: CKRecord) -> Int? {
        let value = record[key]
        if let int = value as? Int {
            return int
        }
        if let int64 = value as? Int64 {
            return Int(exactly: int64)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func isMissingRecordError(_ error: CKError) -> Bool {
        if error.code == .unknownItem {
            return true
        }

        guard error.code == .partialFailure,
              let partialErrors = error.partialErrorsByItemID?.values else {
            return false
        }

        return !partialErrors.isEmpty && partialErrors.allSatisfy { partialError in
            (partialError as? CKError)?.code == .unknownItem
        }
    }

    // MARK: - Device-Local Identity

    /// Returns a stable public record name anchored to this device, using the same
    /// formula as the iCloud path so QR codes and nearby sharing stay compatible.
    /// The device binding key is generated once and stored in Keychain.
    func deviceLocalPublicRecordName(for userId: Int) -> String {
        let key = deviceLocalBindingKey(for: userId)
        return ProfileIdentity.publicRecordName(userId: userId, bindingKey: key)
    }

    /// Generates or retrieves a stable SHA256-derived binding key anchored to this device.
    /// Stored in Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    private func deviceLocalBindingKey(for userId: Int) -> String {
        let keychainKey = "deviceIdentity.bindingKey.\(userId)"
        if let existing = try? KeychainManager.shared.retrieveString(for: keychainKey) {
            return existing
        }
        // First run: generate a random UUID, hash it (same style as iCloud binding key)
        let raw = "fju-aio-device-identity:\(userId):\(UUID().uuidString)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        try? KeychainManager.shared.save(key, for: keychainKey)
        return key
    }
}
