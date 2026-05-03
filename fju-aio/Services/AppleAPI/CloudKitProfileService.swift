import Foundation
import CloudKit
import os.log

// MARK: - CloudKitProfileService
// Stores/retrieves public profiles in CloudKit's public database.
// No school credentials are ever stored here.

actor CloudKitProfileService {
    static let shared = CloudKitProfileService()

    private let container = CKContainer(identifier: "iCloud.com.nelsongx.apps.fju-aio")
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "CloudKit")

    private init() {}

    private enum FriendScheduleField {
        static let recordType = "FriendScheduleShare"
        static let ownerRecordName = "ownerRecordName"
        static let ownerEmpNo = "ownerEmpNo"
        static let scheduleSnapshotData = "scheduleSnapshotData"
        static let lastUpdated = "lastUpdated"
    }

    // MARK: - Publish Own Profile

    func publishProfile(_ profile: PublicProfile) async throws {
        let recordID = CKRecord.ID(recordName: profile.cloudKitRecordName)

        // Fetch the existing record so we have a valid recordChangeTag.
        // Creating a brand-new CKRecord for an already-existing record causes
        // CloudKit to silently drop the save under .ifServerRecordUnchanged policy.
        let record: CKRecord
        do {
            record = try await publicDB.record(for: recordID)
            logger.info("📥 Fetched existing CKRecord for update")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist yet — create fresh
            record = CKRecord(recordType: PublicProfile.CKField.recordType, recordID: recordID)
            logger.info("🆕 No existing record, creating new CKRecord")
        }

        record[PublicProfile.CKField.userId] = profile.userId as CKRecordValue
        record[PublicProfile.CKField.empNo] = profile.empNo as CKRecordValue
        record[PublicProfile.CKField.displayName] = profile.displayName as CKRecordValue
        record[PublicProfile.CKField.avatarURLString] = profile.avatarURLString as CKRecordValue?
        record[PublicProfile.CKField.bio] = profile.bio as CKRecordValue?
        record[PublicProfile.CKField.lastUpdated] = profile.lastUpdated as CKRecordValue

        if let linksData = try? JSONEncoder().encode(profile.socialLinks) {
            record[PublicProfile.CKField.socialLinksData] = linksData as CKRecordValue
            logger.info("📎 socialLinksData: \(linksData.count, privacy: .public) bytes (\(profile.socialLinks.count, privacy: .public) links)")
        }

        if let snapshot = profile.scheduleSnapshot {
            do {
                let snapshotData = try JSONEncoder().encode(snapshot)
                record[PublicProfile.CKField.scheduleSnapshotData] = snapshotData as CKRecordValue
                logger.info("📅 scheduleSnapshotData: \(snapshotData.count, privacy: .public) bytes — semester=\(snapshot.semester, privacy: .public), courses=\(snapshot.courses.count, privacy: .public)")
            } catch {
                logger.error("❌ Failed to encode scheduleSnapshot: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            record[PublicProfile.CKField.scheduleSnapshotData] = nil
            logger.info("📅 scheduleSnapshotData: cleared (snapshot is nil)")
        }

        logger.info("☁️ Saving CKRecord — type=\(PublicProfile.CKField.recordType, privacy: .public), recordName=\(profile.cloudKitRecordName, privacy: .public)")
        _ = try await publicDB.modifyRecords(saving: [record], deleting: [])
        logger.info("✅ Published profile for \(profile.displayName, privacy: .public)")
    }

    // MARK: - Fetch a Friend's Profile

    func fetchProfile(recordName: String) async throws -> PublicProfile? {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let record = try await publicDB.record(for: recordID)
            return decode(record: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Fetch Multiple Profiles

    func fetchProfiles(recordNames: [String]) async throws -> [PublicProfile] {
        guard !recordNames.isEmpty else { return [] }
        let ids = recordNames.map { CKRecord.ID(recordName: $0) }
        let results = try await publicDB.records(for: ids)
        return results.values.compactMap { result in
            if case .success(let record) = result { return decode(record: record) }
            return nil
        }
    }

    // MARK: - Fetch Profiles by School IDs

    func fetchProfiles(empNos: [String]) async throws -> [PublicProfile] {
        let normalized = Array(Set(empNos.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !normalized.isEmpty else { return [] }

        var profiles: [PublicProfile] = []
        for chunk in normalized.chunked(into: 100) {
            let query = CKQuery(
                recordType: PublicProfile.CKField.recordType,
                predicate: NSPredicate(format: "%K IN %@", PublicProfile.CKField.empNo, chunk)
            )
            let (matchResults, cursor) = try await publicDB.records(
                matching: query,
                desiredKeys: nil,
                resultsLimit: CKQueryOperation.maximumResults
            )
            profiles.append(contentsOf: matchResults.compactMap { _, result in
                if case .success(let record) = result { return decode(record: record) }
                return nil
            })

            var nextCursor = cursor
            while let cursor = nextCursor {
                let (moreResults, moreCursor) = try await publicDB.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: nil,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                profiles.append(contentsOf: moreResults.compactMap { _, result in
                    if case .success(let record) = result { return decode(record: record) }
                    return nil
                })
                nextCursor = moreCursor
            }
        }
        return profiles
    }

    // MARK: - Friend-only Schedule Share

    func publishFriendSchedule(_ snapshot: FriendScheduleSnapshot, token: String, ownerRecordName: String, ownerEmpNo: String) async throws {
        let recordID = CKRecord.ID(recordName: friendScheduleRecordName(token: token))
        let record: CKRecord
        do {
            record = try await publicDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: FriendScheduleField.recordType, recordID: recordID)
        }

        record[FriendScheduleField.ownerRecordName] = ownerRecordName as CKRecordValue
        record[FriendScheduleField.ownerEmpNo] = ownerEmpNo as CKRecordValue
        record[FriendScheduleField.scheduleSnapshotData] = try JSONEncoder().encode(snapshot) as CKRecordValue
        record[FriendScheduleField.lastUpdated] = snapshot.updatedAt as CKRecordValue

        _ = try await publicDB.modifyRecords(saving: [record], deleting: [])
        logger.info("✅ Published friend-only schedule for \(ownerEmpNo, privacy: .private)")
    }

    func fetchFriendSchedule(token: String) async throws -> FriendScheduleSnapshot? {
        let recordID = CKRecord.ID(recordName: friendScheduleRecordName(token: token))
        do {
            let record = try await publicDB.record(for: recordID)
            guard let data = record[FriendScheduleField.scheduleSnapshotData] as? Data else { return nil }
            return try? JSONDecoder().decode(FriendScheduleSnapshot.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func deleteFriendSchedule(token: String) async throws {
        let recordID = CKRecord.ID(recordName: friendScheduleRecordName(token: token))
        do {
            _ = try await publicDB.modifyRecords(saving: [], deleting: [recordID])
        } catch let error as CKError where isMissingRecordError(error) {
            return
        }
        logger.info("🗑️ Deleted friend-only schedule")
    }

    // MARK: - Delete Own Profile

    func deleteProfile(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            _ = try await publicDB.modifyRecords(saving: [], deleting: [recordID])
        } catch let error as CKError where isMissingRecordError(error) {
            return
        }
        logger.info("🗑️ Deleted CloudKit profile \(recordName)")
    }

    // MARK: - Decode CKRecord → PublicProfile

    private func decode(record: CKRecord) -> PublicProfile? {
        guard
            let userId = record[PublicProfile.CKField.userId] as? Int,
            let empNo = record[PublicProfile.CKField.empNo] as? String,
            let displayName = record[PublicProfile.CKField.displayName] as? String,
            let lastUpdated = record[PublicProfile.CKField.lastUpdated] as? Date
        else { return nil }

        var links: [SocialLink] = []
        if let linksData = record[PublicProfile.CKField.socialLinksData] as? Data {
            links = (try? JSONDecoder().decode([SocialLink].self, from: linksData)) ?? []
        }

        var snapshot: FriendScheduleSnapshot? = nil
        if let snapshotData = record[PublicProfile.CKField.scheduleSnapshotData] as? Data {
            snapshot = try? JSONDecoder().decode(FriendScheduleSnapshot.self, from: snapshotData)
        }

        return PublicProfile(
            cloudKitRecordName: record.recordID.recordName,
            userId: userId,
            empNo: empNo,
            displayName: displayName,
            avatarURLString: record[PublicProfile.CKField.avatarURLString] as? String,
            bio: record[PublicProfile.CKField.bio] as? String,
            socialLinks: links,
            scheduleSnapshot: snapshot,
            lastUpdated: lastUpdated
        )
    }

    private func friendScheduleRecordName(token: String) -> String {
        "friendSchedule-\(token)"
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

private nonisolated extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
