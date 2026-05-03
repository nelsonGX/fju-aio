import CloudKit
import CryptoKit
import Foundation
import os.log

enum ProfileIdentity {
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

    private init() {}

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
    func ensureIdentity(for session: SISSession, allowTakeover: Bool = false) async throws -> String {
        let iCloudUserID = try await currentICloudUserID()
        let iCloudBindingKey = bindingKey(for: iCloudUserID)
        let publicRecordName = ProfileIdentity.publicRecordName(userId: session.userId, bindingKey: iCloudBindingKey)

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
        let recordID = CKRecord.ID(recordName: friendListRecordName(userId: userId))
        do {
            let record = try await privateDB.record(for: recordID)
            return decodeFriendRecords(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return try await fetchLegacyFriendRecords()
        }
    }

    func saveFriendRecords(_ friends: [FriendRecord], userId: Int) async throws {
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

        record[PrivateIdentityField.ownerUserId] = session.userId as CKRecordValue
        record[PrivateIdentityField.empNo] = session.empNo as CKRecordValue
        record[PrivateIdentityField.activePublicRecordName] = publicRecordName as CKRecordValue
        record[PrivateIdentityField.boundICloudUserID] = iCloudBindingKey as CKRecordValue
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
}
