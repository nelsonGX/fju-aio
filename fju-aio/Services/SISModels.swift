import Foundation

// MARK: - Authentication Models

struct SISSession: Codable, Sendable {
    let token: String
    let userId: Int
    let userName: String
    let empNo: String
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

struct LDAPLoginRequest: Codable, Sendable {
    let empNo: String
    let password: String
    let systemSn: Int = 31
}

struct LDAPLoginResponse: Codable, Sendable {
    let success: Bool
    let token: String?
    let userId: Int?
    let userName: String?
    let empNo: String?
    let message: String?
}

struct APILoginRequest: Codable, Sendable {
    let tokenKey: String
}

struct APILoginResponse: Codable, Sendable {
    let success: Bool
    let sessionId: String?
}

// MARK: - User Models

struct SISUserInfo: Codable, Sendable {
    let userId: Int
    let empNo: String
    let userName: String
    let email: String
    let department: String
    let grade: String
}

struct StudentProfile: Codable, Sendable {
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

// MARK: - Score Models

struct ScoreQueryResponse: Codable, Sendable {
    let academicYear: String
    let semester: String
    let courses: [ScoreCourse]
    let semesterGPA: Double
    let totalCredits: Int
}

struct ScoreCourse: Codable, Sendable, Identifiable {
    let courseId: String
    let courseName: String
    let credits: Int
    let score: Double
    let grade: String
    let gpa: Double
    let instructor: String
    
    var id: String { courseId }
}

// MARK: - Certificate Models

struct CertType: Codable, Sendable, Identifiable {
    let value: String
    let text: String
    
    var id: String { value }
}

struct CertTypesResponse: Codable, Sendable {
    let data: [CertType]
}

struct CertApplyRequest: Codable, Sendable {
    let certType: String
    let purpose: String
    let copies: Int
    let language: String
}

struct CertApplyResponse: Codable, Sendable {
    let success: Bool
    let applyId: String?
    let message: String
    let estimatedDate: String?
}

struct CertApplyRecord: Codable, Sendable, Identifiable {
    let applyId: String
    let certType: String
    let applyDate: String
    let status: String
    let downloadUrl: String?
    
    var id: String { applyId }
}

struct CertApplyListResponse: Codable, Sendable {
    let data: [CertApplyRecord]
}

struct CertVerifyRequest: Codable, Sendable {
    let certId: String
    let verifyCode: String
}

struct CertVerifyResponse: Codable, Sendable {
    let valid: Bool
    let certType: String?
    let studentName: String?
    let studentId: String?
    let issueDate: String?
    let expiryDate: String?
}

// MARK: - Leave Models

struct LeaveType: Codable, Sendable, Identifiable {
    let typeId: String
    let typeName: String
    let requireProof: Bool
    
    var id: String { typeId }
}

struct LeaveTypesResponse: Codable, Sendable {
    let data: [LeaveType]
}

struct LeaveApplyResponse: Codable, Sendable {
    let success: Bool
    let leaveId: String?
    let message: String
    let status: String?
}

struct LeaveRecord: Codable, Sendable, Identifiable {
    let leaveId: String
    let leaveType: String
    let startDate: String
    let endDate: String
    let hours: Int
    let reason: String
    let status: String
    let applyDate: String
    let approveDate: String?
    let approver: String?
    
    var id: String { leaveId }
}

struct LeaveListResponse: Codable, Sendable {
    let totalCount: Int
    let pageNumber: Int
    let pageSize: Int
    let data: [LeaveRecord]
}

struct LeaveCancelResponse: Codable, Sendable {
    let success: Bool
    let message: String
}

// MARK: - Schedule Models

struct CourseScheduleResponse: Codable, Sendable {
    let academicYear: String
    let semester: String
    let courses: [ScheduleCourse]
}

struct ScheduleCourse: Codable, Sendable, Identifiable {
    let courseId: String
    let courseName: String
    let instructor: String
    let credits: Int
    let schedule: [ClassPeriod]
    
    var id: String { courseId }
}

struct ClassPeriod: Codable, Sendable, Identifiable {
    let dayOfWeek: Int
    let period: String
    let classroom: String
    
    var id: String { "\(dayOfWeek)-\(period)-\(classroom)" }
}

// MARK: - Announcement Models

struct AnnouncementResponse: Codable, Sendable {
    let totalCount: Int
    let pageNumber: Int
    let pageSize: Int
    let data: [SISAnnouncement]
}

struct SISAnnouncement: Codable, Sendable, Identifiable {
    let announceId: Int
    let title: String
    let content: String
    let publishDate: String
    let effectiveDate: String
    let expiryDate: String
    let announceType: String?
    
    var id: Int { announceId }
}

// MARK: - Error Models

enum SISError: LocalizedError {
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
