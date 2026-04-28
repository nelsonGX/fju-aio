import Foundation

// MARK: - Authentication Models

nonisolated struct SISSession: Codable, Sendable {
    let token: String
    let userId: Int
    let userName: String
    let empNo: String
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

nonisolated struct LDAPLoginRequest: Codable, Sendable {
    let empNo: String
    let password: String
    let systemSn: Int
    
    init(empNo: String, password: String, systemSn: Int = 31) {
        self.empNo = empNo
        self.password = password
        self.systemSn = systemSn
    }
}

nonisolated struct LDAPLoginResponse: Codable, Sendable {
    let statusCode: Int
    let result: LoginResult?
    let message: [String: String]?
    let errorMessage: [String]
    
    var success: Bool {
        statusCode == 200 && result != nil
    }
    
    var token: String? {
        result?.auth_token
    }
    
    struct LoginResult: Codable, Sendable {
        let auth_token: String
        let refresh_token: String
        let expires_in: Int
        let token_type: String
    }
}

nonisolated struct APILoginRequest: Codable, Sendable {
    let tokenKey: String
}

nonisolated struct APILoginResponse: Codable, Sendable {
    let success: Bool
    let sessionId: String?
}

// MARK: - User Models

nonisolated struct SISUserInfo: Codable, Sendable {
    let userId: Int
    let empNo: String
    let userName: String
    let email: String
    let department: String
    let grade: String
}

nonisolated struct StudentProfile: Codable, Sendable {
    let studentId: String
    let name: String
    let englishName: String
    let idNumber: String
    let birthday: String
    let gender: String
    let email: String
    let phone: String
    let address: String
    let department: String
    let grade: String
    let status: String
    let admissionYear: String
}

nonisolated struct StuBaseInfoResponse: Codable, Sendable {
    let statusCode: Int
    let result: StuBaseInfo
    let message: [String: String]?
    let errorMessage: [String]
    
    struct StuBaseInfo: Codable, Sendable {
        let dayNa: String
        let dptGrdNa: String
        let stuNo: String
        let stuCna: String
        let stuEna: String
        let regEntYear: Int
        let entAcaYear: Int
        let chineseAbility: String?
        let englishAbility: String?
        let inforAbility: String?
        let grd: String?
    }
}

// MARK: - Score Models

nonisolated struct GradesInquiryResponse: Codable, Sendable {
    let statusCode: Int
    let result: [GradeRecord]
    let message: [String: String]?
    let errorMessage: [String]
    
    struct GradeRecord: Codable, Sendable {
        let hy: Int
        let htPeriod: Int
        let reqSelCNa: String
        let couCNa: String
        let credit: Int
        let termNa: String
        let gInfo: String?
        let scoreDisplay: String
        let confirmType: String
        let scoTypCNa: String
        let deferNote: String
        let couClassify: [CourseClassify]?

        var courseIdentifier: String {
            if let avaCouSn = couClassify?.first?.avaCouSn {
                return "\(avaCouSn)"
            }

            return "\(hy)-\(htPeriod)-\(couCNa)"
        }
    }

    struct CourseClassify: Codable, Sendable {
        let avaCouSn: Int
        let couClassifyNo: Int
        let couClassifyCna: String
        let couClassifyEna: String
        let couClassifyNoteCna: String
        let couClassifyNoteEna: String
        let displayOrder: Int
    }
}

nonisolated struct ScoreQueryResponse: Codable, Sendable {
    let academicYear: String
    let semester: String
    let courses: [ScoreCourse]
    let semesterGPA: Double
    let totalCredits: Int
    let earnedCredits: Int
}

nonisolated struct ScoreCourse: Codable, Sendable, Identifiable {
    let courseId: String
    let courseName: String
    let credits: Int
    let score: Double?
    let grade: String
    let gpa: Double
    let instructor: String
    
    var id: String { courseId }
}

// MARK: - Certificate Models

/// Response from GET /Education/api/OnlineStuStatusCertApply/GetStuInfo
nonisolated struct StuStatusCertInfoResponse: Codable, Sendable {
    let statusCode: Int
    let result: StuStatusCertInfo
    let message: AnyCodable?
    let errorMessage: [String]
}

nonisolated struct StuStatusCertInfo: Codable, Sendable {
    let stuNo: String
    let stuCNa: String
    let stuENa: String
    let dayNgt: String
    let dayNa: String
    let dptNa: String
    let dptNo: String
    let grd: String
    let hisStuStatusInfo: [StuStatusRecord]
}

/// One semester entry returned by GetStuInfo
nonisolated struct StuStatusRecord: Codable, Sendable, Identifiable, Hashable {
    let hy: Int
    let ht: Int
    let stuNo: String
    let dayNa: String
    let dptGrdNa: String
    let grd: String
    let cur: String
    let curNa: String
    let isReg: Bool
    let isSubmissionC: Bool
    let isSubmissionE: Bool
    let isCurrent: Bool
    let funcTw: String
    let funcEn: String

    var id: String { "\(hy)-\(ht)" }

    /// Human-readable semester label, e.g. "114學年第2學期"
    var semesterLabel: String { "\(hy)學年第\(ht)學期" }
}

/// Flexible container for JSON values that may be {} or a string
nonisolated struct AnyCodable: Codable, Sendable {
    init(from decoder: Decoder) throws {
        // Accept any JSON value; we don't need to read it
        _ = try? decoder.singleValueContainer()
    }
    func encode(to encoder: Encoder) throws {}
}

// MARK: - Leave Models (matching real exploreLink API)

/// One leave record from GET /StuLeave
nonisolated struct LeaveRecord: Codable, Sendable, Identifiable {
    let leaveApplySn: Int
    let hy: Int
    let ht: Int
    let leaveKind: Int
    let examKind: Int
    let refLeaveSn: Int
    let applyNo: String
    let stuNo: String
    let beginDate: String        // "yyyy-MM-dd'T'HH:mm:ss"
    let endDate: String
    let beginSectNo: Int
    let endSectNo: Int
    let beginDateWekCna: String
    let endDateWekCna: String
    let leaveReason: String
    let totalDay: Int
    let totalSect: Int
    let applyStatus: Int         // 0=編輯中, 1=待審, 9=通過, 5=駁回
    let applyTime: String?
    let leaveKindNa: String
    let leaveNa: String          // e.g. "事假", "病假"
    let applyStatusNa: String
    let stuCna: String
    let beginSectNa: String
    let endSectNa: String

    var id: Int { leaveApplySn }
}

nonisolated struct LeaveListResponse: Codable, Sendable {
    let statusCode: Int
    let result: LeaveListResult
    let message: AnyCodable?
    let errorMessage: AnyCodable?

    struct LeaveListResult: Codable, Sendable {
        let pageNumber: Int
        let pageSize: Int
        let totalPages: Int
        let totalCount: Int
        let result: [LeaveRecord]
    }

    nonisolated var data: [LeaveRecord] { result.result }
}

// MARK: - Schedule Models

nonisolated struct CourseScheduleResponse: Codable, Sendable {
    let academicYear: String
    let semester: String
    let courses: [ScheduleCourse]
}

nonisolated struct ScheduleCourse: Codable, Sendable, Identifiable {
    let courseId: String
    let courseName: String
    let instructor: String
    let credits: Int
    let schedule: [ClassPeriod]
    
    var id: String { courseId }
}

nonisolated struct ClassPeriod: Codable, Sendable, Identifiable {
    let dayOfWeek: Int
    let period: String
    let classroom: String
    
    var id: String { "\(dayOfWeek)-\(period)-\(classroom)" }
}

// MARK: - Announcement Models

nonisolated struct AnnouncementResponse: Codable, Sendable {
    let statusCode: Int
    let result: AnnouncementResult
    
    struct AnnouncementResult: Codable, Sendable {
        let totalItemCount: Int
        let pageNumber: Int
        let pageSize: Int
        let totalPages: Int
        let result: [SISAnnouncement]
    }
}

nonisolated struct SISAnnouncement: Codable, Sendable, Identifiable {
    let announcementSn: Int
    let systemSn: Int
    let systemName: String
    let announceType: Int
    let announceCNa: String
    let title: String
    let announceData: String
    let publishDate: String?
    let effectiveDate: String?
    let expiryDate: String?
    
    var id: Int { announcementSn }
}

// MARK: - Error Models

nonisolated enum SISError: LocalizedError {
    case invalidCredentials
    case tokenExpired
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case unauthorized
    case notFound
    case badRequest(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "帳號或密碼錯誤"
        case .tokenExpired: return "登入已過期，請重新登入"
        case .networkError(let error): return "網路錯誤: \(error.localizedDescription)"
        case .invalidResponse: return "伺服器回應無效"
        case .serverError(let message): return "伺服器錯誤: \(message)"
        case .unauthorized: return "未授權，請先登入"
        case .notFound: return "資源不存在"
        case .badRequest(let message): return "請求錯誤: \(message)"
        }
    }
}
