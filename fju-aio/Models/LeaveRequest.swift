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

// MARK: - Generic coding key

nonisolated struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - Leave reference data

nonisolated struct LeaveKind: Identifiable, Codable, Sendable, Hashable {
    let value: Int
    let label: String
    let lcId: Int?
    let activeFlag: Int?
    let genderKind: Int?
    let isReqFamType: Bool?
    let isReqFamLevel: Bool?

    var id: Int { value }
    var refLeaveSn: Int { value }
    var leaveCna: String { label }
    var leaveNa: String { label }

    var requiresFamilyFields: Bool { isReqFamType == true || isReqFamLevel == true }
    var femaleOnly: Bool { genderKind == 2 }
    var maleOnly: Bool { genderKind == 1 }

    init(
        value: Int,
        label: String,
        lcId: Int? = nil,
        activeFlag: Int? = nil,
        genderKind: Int? = nil,
        isReqFamType: Bool? = nil,
        isReqFamLevel: Bool? = nil
    ) {
        self.value = value
        self.label = label
        self.lcId = lcId
        self.activeFlag = activeFlag
        self.genderKind = genderKind
        self.isReqFamType = isReqFamType
        self.isReqFamLevel = isReqFamLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)

        if let value = try? c.decode(Int.self, forKey: AnyCodingKey("value")) {
            self.value = value
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("label"))) ?? ""
            self.lcId = try? c.decode(Int.self, forKey: AnyCodingKey("lcId"))
        } else if let refLeaveSn = try? c.decode(Int.self, forKey: AnyCodingKey("refLeaveSn")) {
            self.value = refLeaveSn
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("leaveCna"))) ?? ""
            self.lcId = nil
        } else if let leaveKind = try? c.decode(Int.self, forKey: AnyCodingKey("leaveKind")) {
            self.value = leaveKind
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("leaveKindCna"))) ?? ""
            self.lcId = nil
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "LeaveKind: no recognised key"))
        }

        self.activeFlag = try? c.decode(Int.self, forKey: AnyCodingKey("activeFlag"))
        self.genderKind = try? c.decode(Int.self, forKey: AnyCodingKey("genderKind"))
        self.isReqFamType = try? c.decode(Bool.self, forKey: AnyCodingKey("isReqFamType"))
        self.isReqFamLevel = try? c.decode(Bool.self, forKey: AnyCodingKey("isReqFamLevel"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(value, forKey: AnyCodingKey("value"))
        try c.encode(label, forKey: AnyCodingKey("label"))
        try c.encodeIfPresent(lcId, forKey: AnyCodingKey("lcId"))
        try c.encodeIfPresent(activeFlag, forKey: AnyCodingKey("activeFlag"))
        try c.encodeIfPresent(genderKind, forKey: AnyCodingKey("genderKind"))
        try c.encodeIfPresent(isReqFamType, forKey: AnyCodingKey("isReqFamType"))
        try c.encodeIfPresent(isReqFamLevel, forKey: AnyCodingKey("isReqFamLevel"))
    }
}

nonisolated struct LeaveCategory: Identifiable, Codable, Sendable, Hashable {
    let leaveKind: Int
    let leaveKindCna: String

    var id: Int { leaveKind }
    var value: Int { leaveKind }
    var label: String { leaveKindCna }
}

struct RefLeave: Identifiable, Codable, Sendable, Hashable {
    let refLeaveSn: Int
    let leaveCna: String
    let leaveCmemo: String?
    let activeFlag: Int?
    let examActiveFlag: Int?
    let displayOrder: Int?
    let examDisplayOrder: Int?
    let isReqFamType: Bool?
    let isReqFamLevel: Bool?
    let docList: [LeaveDocMapping]?
    let quizDocList: [LeaveDocMapping]?
    let examDocList: [LeaveDocMapping]?
    let isLeaveFlow: Bool?
    let isLeaveFlowQuiz: Bool?
    let isLeaveFlowExam: Bool?

    var id: Int { refLeaveSn }
    var value: Int { refLeaveSn }
    var label: String { leaveCna }
    var leaveNa: String { leaveCna }
    var requiresFamilyFields: Bool { isReqFamType == true || isReqFamLevel == true }
}

struct LeaveDocMapping: Identifiable, Codable, Sendable, Hashable {
    let leaveDocMappingSn: Int
    let leaveKind: Int
    let examKind: Int
    let refLeaveSn: Int
    let refDocSn: Int
    let isRequired: Bool
    let memo: String?
    let docCna: String?

    var id: Int { leaveDocMappingSn }
}

// MARK: - Course sections

nonisolated struct CourseSection: Identifiable, Codable, Sendable, Hashable {
    let sectNo: Int
    let sectNa: String
    let beginTime: String
    let endTime: String

    var id: Int { sectNo }
    var displayLabel: String { "\(sectNa) \(beginTime)-\(endTime)" }
}

nonisolated struct CourseSectionListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [CourseSectionRaw]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct CourseSectionRaw: Codable, Sendable {
    let sectNo: Int
    let sectionCna: String
    let sectionStartTime: String?
    let sectionEndTime: String?

    var resolvedSectNo: Int { sectNo }
    var resolvedSectNa: String { sectionCna }
    var resolvedBeginTime: String { sectionStartTime ?? "" }
    var resolvedEndTime: String { sectionEndTime ?? "" }
}

struct LeaveSectionListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveSection]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

struct LeaveSection: Identifiable, Codable, Sendable, Hashable {
    let refSectionSn: Int?
    let sectNo: Int
    let sectionNo: String?
    let sectionCna: String
    let sectionStartTime: String?
    let sectionEndTime: String?

    var id: Int { sectNo }
    var displayName: String {
        [sectionNo, sectionCna, [sectionStartTime, sectionEndTime].compactMap { $0 }.joined(separator: "-")]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
    }
}

// MARK: - Family type/level and contact

nonisolated struct FamTypeItem: Identifiable, Codable, Sendable, Hashable {
    let value: Int
    let label: String

    var id: Int { value }
    var leaveNa: String { label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        if let value = try? c.decode(Int.self, forKey: AnyCodingKey("famTypeNo")) {
            self.value = value
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("famTypeCna"))) ?? ""
        } else if let value = try? c.decode(Int.self, forKey: AnyCodingKey("value")) {
            self.value = value
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("label"))) ?? ""
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "FamTypeItem: no recognised key"))
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
        if let value = try? c.decode(Int.self, forKey: AnyCodingKey("famLevelNo")) {
            self.value = value
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("famLevelCna"))) ?? ""
        } else if let value = try? c.decode(Int.self, forKey: AnyCodingKey("value")) {
            self.value = value
            self.label = (try? c.decode(String.self, forKey: AnyCodingKey("label"))) ?? ""
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "FamLevelItem: no recognised key"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(value, forKey: AnyCodingKey("value"))
        try c.encode(label, forKey: AnyCodingKey("label"))
    }
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

// MARK: - Leave record detail and selected courses

nonisolated struct LeaveRecordDetailResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveRecord?
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct LeaveSelCouListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveSelCouCourse]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct LeaveSelCouCourse: Codable, Sendable, Identifiable {
    let jonCouSn: Int
    let avaCouSn: Int
    let couCNa: String
    let couNo: String
    let tchCNa: String?
    let dptGrdNa: String?
    let couWek: String
    let sectNos: [Int]
    let leaveDates: [LeaveSelCouDate]

    var id: Int { jonCouSn }
}

nonisolated struct LeaveSelCouDate: Codable, Sendable, Identifiable {
    let couDate: String
    let sectNo: Int
    var isSelected: Bool = true

    var id: String { "\(couDate)-\(sectNo)" }
}

// MARK: - Wizard state and POST payload

nonisolated struct LeaveWizardDraft: Sendable {
    var leaveKind: Int = 1
    var hy: Int = 114
    var ht: Int = 2
    var refLeaveSn: Int = 2
    var beginDate: String = ""
    var endDate: String = ""
    var beginSectNo: Int = 1
    var endSectNo: Int = 9
    var leaveReason: String = ""
    var phoneNumber: String = ""
    var emailAccount: String = ""
    var famTypeNo: Int?
    var famLevelNo: Int?
    var proofFileData: Data?
    var proofFileExt: String = "pdf"
    var proofFileName: String = ""
    var leaveApplySn: Int = 0
    var applyNo: String = ""
}

nonisolated struct SelCouPostEntry: Codable, Sendable {
    let jonCouSn: Int
    let avaCouSn: Int
    let stuNo: String
    let couWek: String
    let seqTims: [SelCouSeqTim]
    let couDates: [String]
}

nonisolated struct SelCouSeqTim: Codable, Sendable {
    let section: String
    let leaveSeqTimSn: Int
    let leaveApplySn: Int
    let jonCouSn: Int
    let avaCouSn: Int
    let stuNo: String?
    let couDate: String
    let couWek: String
    let sectNo: Int
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

struct RefLeaveListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [RefLeave]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

struct LeaveDetailResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveDetail
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

struct LeaveDetail: Codable, Sendable, Identifiable, Hashable {
    let leaveApplySn: Int
    let hy: Int
    let ht: Int
    let leaveKind: Int
    let examKind: Int
    let refLeaveSn: Int
    let applyNo: String
    let stuNo: String
    let beginDate: String
    let endDate: String
    let beginSectNo: Int
    let endSectNo: Int
    let leaveReason: String
    let applyStatus: Int?
    let applyStatusNa: String?
    let officialLeaveSn: Int
    let phoneNumber: String?
    let emailAccount: String?
    let famTypeNo: Int?
    let famLevelNo: Int?
    let leaveKindNa: String
    let examKindNa: String?
    let leaveNa: String
    let beginSectNa: String?
    let endSectNa: String?
    let totalDay: Int?
    let totalSect: Int?
    let leaveApplyDocs: [LeaveApplyDoc]
    let snHash: String?

    var id: Int { leaveApplySn }
}

struct LeaveApplyDoc: Identifiable, Codable, Sendable, Hashable {
    let leaveApplyDocSn: Int
    let leaveApplySn: Int
    let officialLeaveSn: Int?
    let refDocSn: Int
    let docNa: String?
    let docMemo: String?
    let fileRawName: String?
    let checkStatus: Int?

    var id: Int { leaveApplyDocSn }
}

struct LeaveApplyAPIResponse: Codable, Sendable {
    let statusCode: Int
    let result: Int?
    let message: LeaveMessage?
    let errorMessage: [LeaveErrorField]?

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

struct LeaveBoolResponse: Codable, Sendable {
    let statusCode: Int
    let result: Bool
    let message: LeaveMessage?
    let errorMessage: AnyCodable?

    struct LeaveMessage: Codable, Sendable {
        let info: String?
    }

    nonisolated var success: Bool { statusCode == 200 && result }
}

// MARK: - Leave stat from StuLeave/Stat

nonisolated struct LeaveStat: Sendable {
    let leaveName: String
    let totalSections: Int
    let totalDays: Int
}

nonisolated struct LeaveStatResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveStatSummary
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

typealias LeaveStatResult = LeaveStatSummary
typealias LeaveStatCourse = LeaveStatRecord
typealias LeaveStatListResponse = LeaveStatResponse

nonisolated struct LeaveStatSummary: Codable, Sendable {
    let stuNo: String
    let sumLeaveSect: Int
    let sumLeaveSectYes: Int
    let sumLeaveSectNo: Int
    let statLeaveCouList: [LeaveStatRecord]
}

nonisolated struct LeaveStatRecord: Codable, Sendable, Identifiable {
    let stuNo: String?
    let cntLeaveSect: Int
    let cntLeaveSectYes: Int
    let cntLeaveSectNo: Int
    let leaveSeqTims: [LeaveStatLeaveSeqTim]
    let jonCouSn: Int
    let avaCouSn: Int
    let hy: Int
    let ht: Int
    let scoTyp: Int?
    let period: Int?
    let avaDivCn: String?
    let avaDptCn: String?
    let javaNo: String?
    let avaNo: String?
    let couCna: String
    let couEna: String?
    let reqSel: String?
    let reqSelCna: String?
    let credit: Double?
    let errLab: String?
    let memo: String?
    let tchNo: String?
    let tchCna: String?
    let tchEna: String?
    let seqTims: [LeaveStatSeqTim]
    let sumSect: Int

    var id: Int { jonCouSn }
    var courseCode: String { javaNo ?? avaNo ?? "" }
    var courseName: String { couCna.isEmpty ? (avaNo ?? "未命名課程") : couCna }
    var teacherName: String { tchCna?.isEmpty == false ? tchCna! : (tchEna ?? "") }
    var scheduleText: String { seqTims.map(\.displayText).joined(separator: "、") }
}

nonisolated struct LeaveStatSeqTim: Codable, Sendable, Identifiable, Hashable {
    let seqTimSn: Int?
    let avaCouSn: Int?
    let sda: String?
    let couWek: String?
    let couWekCna: String?
    let couWekEna: String?
    let couWekNa: String?
    let section: String
    let sect: String?
    let sectNo: Int
    let couDate: String?
    let weeklyCna: String?
    let weeklyEna: String?
    let weeklyNa: String?
    let romNo: String?
    let dateTimeGroup: Int?
    let couCna: String?
    let isEvenWek: Bool?
    let holidayName: String?
    let dayPeriodKind: Int?
    let holidayDiv: String?

    var id: Int { seqTimSn ?? sectNo }
    var displayText: String {
        if let couWekNa, !couWekNa.isEmpty {
            return "\(couWekNa) \(section)"
        }
        if let couWekCna, !couWekCna.isEmpty {
            return "\(couWekCna) \(section)"
        }
        return section
    }
}

nonisolated struct LeaveStatLeaveSeqTim: Codable, Sendable, Identifiable, Hashable {
    let section: String
    let leaveSeqTimSn: Int?
    let leaveApplySn: Int?
    let jonCouSn: Int?
    let avaCouSn: Int?
    let stuNo: String?
    let couDate: String?
    let couWek: String?
    let sectNo: Int

    var id: String { "\(couDate ?? "")-\(section)-\(sectNo)" }
    var displayDate: String? { couDate.map { String($0.prefix(10)) } }
}

nonisolated struct LeaveApplyDeadlineResponse: Codable, Sendable {
    let statusCode: Int
    let result: String?
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

// MARK: - Approval flow from GET /StuLeave/{sn}/SelCou/ApplyResult

nonisolated struct LeaveApplyResultResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveApplyResult]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

nonisolated struct LeaveApplyResult: Codable, Sendable, Identifiable {
    let leaveApplySn: Int
    let leaveSelCouSn: Int
    let avaCouSn: Int
    let javaNo: String?
    let couCna: String
    let couEna: String?
    let tchCna: String?
    let tchEna: String?
    let couDates: [String]?
    let seqTims: [String]?
    let applyStatus: Int
    let applyStatusNa: String
    let auditTime: String?
    let auditOpinion: String?
    let flowInstanceSn: Int?

    var id: Int { leaveSelCouSn }
}

// MARK: - Cancel (revoke) leave response

nonisolated struct LeaveCancelResponse: Codable, Sendable {
    let statusCode: Int
    let result: Bool?
    let message: LeaveCancelMessage?
    let errorMessage: AnyCodable?

    struct LeaveCancelMessage: Codable, Sendable {
        let info: String?
    }
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
