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

// MARK: - Leave reference data
// API shape: {"value": 1, "label": "一般請假", "lcId": 0}

struct LeaveKind: Identifiable, Codable, Sendable, Hashable {
    let value: Int
    let label: String
    let lcId: Int

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
    var leaveNa: String { label }
}

struct RefLeave: Identifiable, Codable, Sendable, Hashable {
    let refLeaveSn: Int
    let leaveCna: String
    let leaveCmemo: String
    let activeFlag: Int
    let examActiveFlag: Int
    let displayOrder: Int
    let examDisplayOrder: Int
    let isReqFamType: Bool
    let isReqFamLevel: Bool
    let docList: [LeaveDocMapping]
    let quizDocList: [LeaveDocMapping]
    let examDocList: [LeaveDocMapping]
    let isLeaveFlow: Bool
    let isLeaveFlowQuiz: Bool
    let isLeaveFlowExam: Bool

    var id: Int { refLeaveSn }
    var leaveNa: String { leaveCna }
}

struct LeaveDocMapping: Identifiable, Codable, Sendable, Hashable {
    let leaveDocMappingSn: Int
    let leaveKind: Int
    let examKind: Int
    let refLeaveSn: Int
    let refDocSn: Int
    let isRequired: Bool
    let memo: String
    let docCna: String

    var id: Int { leaveDocMappingSn }
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

struct RefLeaveListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [RefLeave]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

struct LeaveSectionListResponse: Codable, Sendable {
    let statusCode: Int
    let result: [LeaveSection]
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

struct LeaveSection: Identifiable, Codable, Sendable, Hashable {
    let refSectionSn: Int
    let sectNo: Int
    let sectionNo: String
    let sectionCna: String
    let sectionStartTime: String
    let sectionEndTime: String

    var id: Int { sectNo }
    var displayName: String {
        "\(sectionNo) \(sectionCna) \(sectionStartTime)-\(sectionEndTime)"
    }
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
    let phoneNumber: String
    let emailAccount: String
    let famTypeNo: Int
    let famLevelNo: Int
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
    let officialLeaveSn: Int
    let refDocSn: Int
    let docNa: String?
    let docMemo: String?
    let fileRawName: String
    let checkStatus: Int

    var id: Int { leaveApplyDocSn }
}

struct LeaveApplyAPIResponse: Codable, Sendable {
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

struct LeaveStatListResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveStatResult
    let message: AnyCodable?
    let errorMessage: AnyCodable?
}

struct LeaveStatResult: Codable, Sendable {
    let stuNo: String
    let sumLeaveSect: Int
    let sumLeaveSectYes: Int
    let sumLeaveSectNo: Int
    let statLeaveCouList: [LeaveStatCourse]
}

struct LeaveStatCourse: Codable, Sendable, Identifiable {
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
    let couCna: String?
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
    var courseName: String { couCna?.isEmpty == false ? couCna! : (avaNo ?? "未命名課程") }
    var teacherName: String { tchCna?.isEmpty == false ? tchCna! : (tchEna ?? "") }
    var scheduleText: String {
        let items = seqTims.compactMap { item -> String? in
            guard let section = item.section?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !section.isEmpty else {
                return nil
            }
            if let week = item.couWekNa?.trimmingCharacters(in: .whitespacesAndNewlines), !week.isEmpty {
                return "\(week) \(section)"
            }
            return section
        }
        return Array(Set(items)).sorted().joined(separator: "、")
    }
}

struct LeaveStatSeqTim: Codable, Sendable, Hashable {
    let seqTimSn: Int?
    let avaCouSn: Int?
    let sda: String?
    let couWek: String?
    let couWekCna: String?
    let couWekEna: String?
    let couWekNa: String?
    let section: String?
    let sect: String?
    let sectNo: Int?
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
}

struct LeaveStatLeaveSeqTim: Codable, Sendable, Hashable {
    let section: String?
    let leaveSeqTimSn: Int?
    let leaveApplySn: Int?
    let jonCouSn: Int?
    let avaCouSn: Int?
    let stuNo: String?
    let couDate: String?
    let couWek: String?
    let sectNo: Int?
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
