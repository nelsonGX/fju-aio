import Foundation

// MARK: - App-level leave model (used by UI)

nonisolated struct LeaveRequest: Identifiable, Sendable {
    let id: String              // leaveApplySn as string
    let leaveApplySn: Int
    let applyNo: String
    let leaveKindName: String   // 一般請假 / 公假
    let leaveName: String       // 病假 / 事假 / etc.
    let refLeaveSn: Int         // foreign key into RefList/LeaveKind
    let beginDate: Date
    let endDate: Date
    let beginSectNo: Int
    let endSectNo: Int
    let beginSectName: String
    let endSectName: String
    let reason: String
    let totalDays: Int
    let totalSections: Int
    let applyStatus: Int
    let applyStatusName: String
    let applyTime: String

    var statusColor: StatusColor {
        switch applyStatus {
        case 9: return .approved
        case 1: return .pending
        case 5: return .rejected
        default: return .pending
        }
    }

    enum StatusColor { case approved, pending, rejected, draft }
}

// MARK: - Leave subtype from GET /RefList/RefLeave
// Actual API shape: {"refLeaveSn":2,"leaveCna":"事假","activeFlag":1,...}

nonisolated struct LeaveKind: Identifiable, Codable, Sendable, Hashable {
    let refLeaveSn: Int
    let leaveCna: String        // e.g. "事假", "病假"
    let activeFlag: Int?
    let genderKind: Int?        // 0=不分, 1=男, 2=女
    let isReqFamType: Bool?
    let isReqFamLevel: Bool?

    var id: Int { refLeaveSn }
    var value: Int { refLeaveSn }
    var label: String { leaveCna }
    var leaveNa: String { leaveCna }

    /// True when this subtype requires 親屬 family fields (e.g. 喪假)
    var requiresFamilyFields: Bool { isReqFamType == true || isReqFamLevel == true }
    /// True when only available to female students
    var femaleOnly: Bool { genderKind == 2 }
    /// True when only available to male students
    var maleOnly: Bool { genderKind == 1 }
}

// MARK: - Leave category from GET /RefList/LeaveKind (top-level: 一般/考試)
// Actual API shape: {"leaveKind":1,"leaveKindCna":"一般請假",...}

nonisolated struct LeaveCategory: Identifiable, Codable, Sendable, Hashable {
    let leaveKind: Int
    let leaveKindCna: String

    var id: Int { leaveKind }
    var value: Int { leaveKind }
    var label: String { leaveKindCna }
}

// MARK: - Course section from GET /Course/Section

nonisolated struct CourseSection: Identifiable, Codable, Sendable, Hashable {
    let sectNo: Int             // 1–9 numeric key
    let sectNa: String          // e.g. "D5"
    let beginTime: String       // e.g. "13:40"
    let endTime: String         // e.g. "14:30"

    var id: Int { sectNo }
    var displayLabel: String { "\(sectNa) \(beginTime)–\(endTime)" }
}

nonisolated struct CourseSectionListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [CourseSectionRaw]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct CourseSectionRaw: Codable, Sendable {
    let sectNo: Int
    let sectionCna: String          // e.g. "D5"
    let sectionStartTime: String?   // e.g. "13:40"
    let sectionEndTime: String?     // e.g. "14:30"

    var resolvedSectNo: Int { sectNo }
    var resolvedSectNa: String { sectionCna }
    var resolvedBeginTime: String { sectionStartTime ?? "" }
    var resolvedEndTime: String { sectionEndTime ?? "" }
}

// MARK: - Family type/level from RefList/FamType, RefList/FamLevel
// Using flexible decoding to handle various possible field name shapes

nonisolated struct FamTypeItem: Identifiable, Codable, Sendable, Hashable {
    let value: Int
    let label: String
    var id: Int { value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        // Try known field name variations
        if let v = try? c.decode(Int.self, forKey: AnyCodingKey("famTypeNo")) {
            value = v
            label = (try? c.decode(String.self, forKey: AnyCodingKey("famTypeCna"))) ?? ""
        } else if let v = try? c.decode(Int.self, forKey: AnyCodingKey("value")) {
            value = v
            label = (try? c.decode(String.self, forKey: AnyCodingKey("label"))) ?? ""
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "FamTypeItem: no recognised key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(value, forKey: AnyCodingKey("value"))
        try c.encode(label, forKey: AnyCodingKey("label"))
    }
}

nonisolated struct FamLevelItem: Identifiable, Codable, Sendable, Hashable {
    let value: Int
    let label: String
    var id: Int { value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        if let v = try? c.decode(Int.self, forKey: AnyCodingKey("famLevelNo")) {
            value = v
            label = (try? c.decode(String.self, forKey: AnyCodingKey("famLevelCna"))) ?? ""
        } else if let v = try? c.decode(Int.self, forKey: AnyCodingKey("value")) {
            value = v
            label = (try? c.decode(String.self, forKey: AnyCodingKey("label"))) ?? ""
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "FamLevelItem: no recognised key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(value, forKey: AnyCodingKey("value"))
        try c.encode(label, forKey: AnyCodingKey("label"))
    }
}

/// Generic CodingKey for dynamic key lookup
nonisolated struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

nonisolated struct FamTypeListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [FamTypeItem]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct FamLevelListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [FamLevelItem]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

// MARK: - Student contact pre-fill from GET /Student/Contact

nonisolated struct StudentContactResponse: Codable, Sendable {
    let statusCode: Int
    let result: StudentContact?
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct StudentContact: Codable, Sendable {
    let phoneNumber: String?
    let emailAccount: String?
}

// MARK: - Full leave record from GET /StuLeave/{sn}

nonisolated struct LeaveRecordDetailResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveRecord?
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

// MARK: - Course list from GET /StuLeave/{sn}/SelCou

nonisolated struct LeaveSelCouListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveSelCouCourse]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

/// One course entry returned by GET /StuLeave/{sn}/SelCou
nonisolated struct LeaveSelCouCourse: Codable, Sendable, Identifiable {
    let jonCouSn: Int
    let avaCouSn: Int
    let couCNa: String          // Course name
    let couNo: String           // Course code
    let tchCNa: String?         // Teacher name
    let dptGrdNa: String?       // e.g. "(日)資管二甲"
    let couWek: String          // Day of week "1"–"7"
    let sectNos: [Int]          // Period numbers this course occupies
    let leaveDates: [LeaveSelCouDate]  // Dates that overlap the leave

    var id: Int { jonCouSn }
}

nonisolated struct LeaveSelCouDate: Codable, Sendable, Identifiable {
    let couDate: String         // ISO8601 date string
    let sectNo: Int
    var isSelected: Bool = true

    var id: String { "\(couDate)-\(sectNo)" }
}

// MARK: - Wizard state shared across steps

nonisolated struct LeaveWizardDraft: Sendable {
    // Step 1
    var leaveKind: Int = 1           // 1=一般請假, 2=考試請假

    // Step 2
    var hy: Int = 114
    var ht: Int = 2
    var refLeaveSn: Int = 2          // Default: 事假
    var beginDate: String = ""
    var endDate: String = ""
    var beginSectNo: Int = 1
    var endSectNo: Int = 9
    var leaveReason: String = ""
    var phoneNumber: String = ""
    var emailAccount: String = ""
    var famTypeNo: Int? = nil
    var famLevelNo: Int? = nil
    var proofFileData: Data? = nil
    var proofFileExt: String = "pdf"
    var proofFileName: String = ""

    // Created by Step 2 → Step 3 transition
    var leaveApplySn: Int = 0
    var applyNo: String = ""
}

// MARK: - POST /StuLeave/{sn}/SelCou payload
// Server requires one entry per course (not per period), with seqTims and couDates arrays.

nonisolated struct SelCouPostEntry: Codable, Sendable {
    let jonCouSn: Int
    let avaCouSn: Int
    let stuNo: String
    let couWek: String
    let seqTims: [SelCouSeqTim]
    let couDates: [String]      // plain date strings e.g. "2026-04-29T00:00:00"
}

nonisolated struct SelCouSeqTim: Codable, Sendable {
    let section: String         // e.g. "D5"
    let leaveSeqTimSn: Int      // 0 for new
    let leaveApplySn: Int
    let jonCouSn: Int
    let avaCouSn: Int
    let stuNo: String?
    let couDate: String         // "2026-04-29T00:00:00"
    let couWek: String
    let sectNo: Int
}

// MARK: - Leave stat from StuLeave/Stat

nonisolated struct LeaveStat: Sendable {
    let leaveName: String
    let totalSections: Int
    let totalDays: Int
}

// MARK: - API response wrappers

nonisolated struct LeaveKindListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveKind]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct LeaveCategoryListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveCategory]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct LeaveApplyAPIResponse: Codable, Sendable {
    let statusCode: Int
    let result: Int?            // the new leaveApplySn (null on error)
    let message: LeaveMessage?
    let errorMessage: [LeaveErrorField]?  // [{key, message}] on 400

    struct LeaveMessage: Codable, Sendable {
        let info: String?
    }

    struct LeaveErrorField: Codable, Sendable {
        let key: String
        let message: String
    }

    nonisolated var success: Bool { statusCode == 200 && (result ?? 0) > 0 }
    nonisolated var leaveApplySn: Int { result ?? 0 }
    nonisolated var errorMessages: [LeaveErrorField]? { errorMessage }
}

nonisolated struct LeaveSelCouResponse: Codable, Sendable {
    let statusCode: Int
    let result: Bool
    let message: LeaveSelCouMessage?
    let errorMessage: AnyCodable?

    struct LeaveSelCouMessage: Codable, Sendable {
        let info: String?
    }

    nonisolated var success: Bool { statusCode == 200 && result }
}

nonisolated struct LeaveStatResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveStatSummary
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct LeaveStatSummary: Codable, Sendable {
    let stuNo: String
    let sumLeaveSect: Int
    let sumLeaveSectYes: Int
    let sumLeaveSectNo: Int
    let statLeaveCouList: [LeaveStatRecord]
}

nonisolated struct LeaveStatRecord: Codable, Sendable, Identifiable {
    let stuNo: String
    let cntLeaveSect: Int
    let cntLeaveSectYes: Int
    let cntLeaveSectNo: Int
    let leaveSeqTims: [LeaveStatLeaveSeqTim]
    let jonCouSn: Int
    let avaCouSn: Int
    let hy: Int
    let ht: Int
    let avaDptCn: String?
    let javaNo: String?
    let avaNo: String?
    let couCna: String
    let credit: Double
    let tchCna: String?
    let seqTims: [LeaveStatSeqTim]
    let sumSect: Int

    var id: Int { jonCouSn }
    var courseCode: String { javaNo ?? avaNo ?? "" }
}

nonisolated struct LeaveStatSeqTim: Codable, Sendable, Identifiable {
    let seqTimSn: Int
    let couWekCna: String?
    let section: String
    let sectNo: Int

    var id: Int { seqTimSn }
    var displayText: String {
        if let couWekCna, !couWekCna.isEmpty {
            return "\(couWekCna) \(section)"
        }
        return section
    }
}

nonisolated struct LeaveStatLeaveSeqTim: Codable, Sendable, Identifiable {
    let section: String
    let couDate: String?
    let sectNo: Int

    var id: String { "\(couDate ?? "")-\(section)-\(sectNo)" }
    var displayDate: String? { couDate.map { String($0.prefix(10)) } }
}

nonisolated struct LeaveApplyDeadlineResponse: Codable, Sendable {
    let statusCode: Int
    let result: String?         // deadline date string
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

// API shape: {"statusCode":200,"result":[114,113],...}
nonisolated struct HyListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [Int]
    let message: AnyCodable?
    let errorMessage: AnyCodable?

    nonisolated var records: [HyRecord] { result.map { HyRecord(hy: $0) } }
}

nonisolated struct HyRecord: Sendable, Identifiable, Hashable {
    let hy: Int

    var id: Int { hy }
    var hyNa: String { "\(hy)學年度" }
}
