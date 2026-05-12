import Foundation

// MARK: - Social Link (dynamic, user-defined)

nonisolated struct SocialLink: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var platform: SocialPlatform
    /// The user-entered handle/value (e.g. "@nelson" or "https://...")
    var handle: String

    /// Resolved URL to open, nil if platform has no URL template
    var resolvedURL: URL? { platform.url(for: handle) }

    /// Display string shown in the row
    var displayHandle: String { platform.displayHandle(for: handle) }
}

// MARK: - Social Platform

nonisolated enum SocialPlatform: String, Codable, CaseIterable, Sendable {
    case instagram
    case discord
    case line
    case telegram
    case threads
    case x           // Twitter/X
    case github
    case facebook
    case youtube
    case other

    var label: String {
        switch self {
        case .instagram: return "Instagram"
        case .discord:   return "Discord"
        case .line:      return "LINE"
        case .telegram:  return "Telegram"
        case .threads:   return "Threads"
        case .x:         return "X (Twitter)"
        case .github:    return "GitHub"
        case .facebook:  return "Facebook"
        case .youtube:   return "YouTube"
        case .other:     return "其他"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera.fill"
        case .discord:   return "gamecontroller.fill"
        case .line:      return "message.fill"
        case .telegram:  return "paperplane.fill"
        case .threads:   return "at"
        case .x:         return "at"
        case .github:    return "chevron.left.forwardslash.chevron.right"
        case .facebook:  return "hand.thumbsup.fill"
        case .youtube:   return "play.rectangle.fill"
        case .other:     return "link"
        }
    }

    var color: String {
        switch self {
        case .instagram: return "#E1306C"
        case .discord:   return "#5865F2"
        case .line:      return "#00C300"
        case .telegram:  return "#2AABEE"
        case .threads:   return "#000000"
        case .x:         return "#000000"
        case .github:    return "#333333"
        case .facebook:  return "#1877F2"
        case .youtube:   return "#FF0000"
        case .other:     return "#8E8E93"
        }
    }

    var placeholder: String {
        switch self {
        case .instagram: return "帳號（不含 @）"
        case .discord:   return "用戶名"
        case .line:      return "LINE ID"
        case .telegram:  return "用戶名（不含 @）"
        case .threads:   return "用戶名（不含 @）"
        case .x:         return "帳號（不含 @）"
        case .github:    return "用戶名"
        case .facebook:  return "個人頁網址或帳號"
        case .youtube:   return "頻道網址或 @帳號"
        case .other:     return "連結名稱或網址"
        }
    }

    func url(for handle: String) -> URL? {
        let h = handle.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return nil }
        switch self {
        case .instagram: return URL(string: "https://instagram.com/\(h)")
        case .discord:   return nil  // No direct profile URL
        case .line:      return URL(string: "https://line.me/ti/p/~\(h)")
        case .telegram:  return URL(string: "https://t.me/\(h)")
        case .threads:   return URL(string: "https://threads.net/@\(h.hasPrefix("@") ? String(h.dropFirst()) : h)")
        case .x:         return URL(string: "https://x.com/\(h)")
        case .github:    return URL(string: "https://github.com/\(h)")
        case .facebook:
            if h.hasPrefix("http") { return URL(string: h) }
            return URL(string: "https://facebook.com/\(h)")
        case .youtube:
            if h.hasPrefix("http") { return URL(string: h) }
            return URL(string: "https://youtube.com/@\(h.hasPrefix("@") ? String(h.dropFirst()) : h)")
        case .other:
            if h.hasPrefix("http") { return URL(string: h) }
            return nil
        }
    }

    func displayHandle(for handle: String) -> String {
        let h = handle.trimmingCharacters(in: .whitespaces)
        switch self {
        case .instagram, .threads, .x, .telegram: return "@\(h)"
        default: return h
        }
    }

    var assetName: String? {
        switch self {
        case .instagram, .discord, .line, .telegram, .threads, .x, .github, .facebook, .youtube:
            return rawValue
        case .other:
            return nil
        }
    }
}

// MARK: - Public Profile (stored in CloudKit public DB)

nonisolated struct PublicProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String { cloudKitRecordName }

    /// CloudKit record name. QR/friend references may use the school-account alias `user-<id>`,
    /// which resolves to the active owner-created profile record.
    let cloudKitRecordName: String

    // School identity (read from SIS session on publish)
    let userId: Int
    let empNo: String
    var displayName: String
    var avatarURLString: String?
    var bio: String?

    var avatarURL: URL? {
        avatarURLString.flatMap { URL(string: $0) }
    }

    // Dynamic social links — user-defined list
    var socialLinks: [SocialLink]

    // Schedule snapshot embedded in profile
    var scheduleSnapshot: FriendScheduleSnapshot?

    var lastUpdated: Date

    // MARK: - CloudKit field names
    nonisolated enum CKField {
        static let recordType = "PublicProfile"
        static let userId = "userId"
        static let empNo = "empNo"
        static let displayName = "displayName"
        static let avatarURLString = "avatarURLString"
        static let bio = "bio"
        static let socialLinksData = "socialLinksData"
        static let scheduleSnapshotData = "scheduleSnapshotData"
        static let lastUpdated = "lastUpdated"
    }
}

// MARK: - Friend Schedule Snapshot
// Non-sensitive subset of a user's course list — safe to publish

nonisolated struct FriendScheduleSnapshot: Codable, Hashable, Sendable {
    let ownerUserId: Int
    let ownerDisplayName: String
    let semester: String
    let courses: [PublicCourseInfo]
    let updatedAt: Date
}

nonisolated enum ScheduleVisibility: String, Codable, CaseIterable, Sendable {
    case off
    case friendsOnly
    case `public`

    var label: String {
        switch self {
        case .off: return "不分享"
        case .friendsOnly: return "只限好友"
        case .public: return "公開"
        }
    }

    var description: String {
        switch self {
        case .off: return "不會把課表同步到雲端。"
        case .friendsOnly: return "課表會用好友 QR Code 內的私密分享碼開放給好友。"
        case .public: return "課表會包含在公開資料中。"
        }
    }

    init(legacyShareSchedule: Bool) {
        self = legacyShareSchedule ? .public : .off
    }
}

nonisolated struct PublicCourseInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(dayOfWeek)-\(startPeriod)-\(name)" }
    let name: String
    let instructor: String
    let dayOfWeek: String
    let startPeriod: Int
    let endPeriod: Int
    let location: String
    let weeks: String

    init(from course: Course) {
        self.name = course.name
        self.instructor = course.instructor
        self.dayOfWeek = course.dayOfWeek
        self.startPeriod = course.startPeriod
        self.endPeriod = course.endPeriod
        self.location = course.location
        self.weeks = course.weeks
    }
}

// MARK: - Local Friend Record (stored in UserDefaults)

nonisolated struct FriendRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String                          // = cloudKitRecordName
    let empNo: String
    var displayName: String
    var cachedProfile: PublicProfile?
    var scheduleShareToken: String?
    let addedAt: Date
    /// True when LDAP credentials for this friend are stored in Keychain.
    /// Not persisted in JSON — recomputed from Keychain on load.
    var hasStoredCredentials: Bool = false

    /// True when this record was created manually (not via QR / CloudKit).
    var isManuallyAdded: Bool { id.hasPrefix("manual-") }

    static func == (lhs: FriendRecord, rhs: FriendRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Group Rollcall Credential Payload
// Embedded in a QR code — user explicitly opts in to share LDAP credentials

nonisolated struct GroupRollcallQRPayload: Codable, Sendable {
    let version: Int
    let type: String                // "group_rollcall"
    let username: String
    let password: String
    let sharerDisplayName: String
    let sharerUserId: Int
    let issuedAt: Date
}

// MARK: - Combined QR Payload
// Carries both profile info and LDAP credentials in a single QR code.
// Scanning this adds the person as a friend AND stores rollcall credentials.

nonisolated struct CombinedQRPayload: Codable, Sendable {
    let version: Int
    let type: String                // "combined"
    let cloudKitRecordName: String
    let empNo: String
    let displayName: String
    let userId: Int
    let username: String
    let password: String
    let scheduleShareToken: String?
    let issuedAt: Date
}

// MARK: - Profile QR Payload

nonisolated struct ProfileQRPayload: Codable, Sendable {
    let version: Int
    let type: String                // "profile"
    let cloudKitRecordName: String
    let empNo: String
    let displayName: String
    let userId: Int
    let scheduleShareToken: String?
}

// MARK: - Mutual Add QR Payload
// Both sides scan once. Person A shows this QR; when B scans it, B's device
// immediately shows their own MutualQR for A to scan back.
// Each scan adds the other person as a friend on that device.

nonisolated struct MutualQRPayload: Codable, Sendable {
    let version: Int
    let type: String                // "mutual"
    let cloudKitRecordName: String
    let empNo: String
    let displayName: String
    let userId: Int
    let scheduleShareToken: String?
}

// MARK: - QR Code Type Discriminator

nonisolated enum ScannedQRType {
    case profile(ProfileQRPayload)
    case groupRollcall(GroupRollcallQRPayload)
    case combined(CombinedQRPayload)
    case mutual(MutualQRPayload)
    case unknown(String)
}
