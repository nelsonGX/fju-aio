import Foundation

// MARK: - Authentication Models

nonisolated struct TronClassSession: Codable, Sendable {
    let sessionId: String
    let userId: Int
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

nonisolated struct CASLoginResponse: Codable, Sendable {
    let user_id: Int
}

// MARK: - Authentication Errors

nonisolated enum AuthenticationError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case invalidResponse
    case serverError(String)
    case sessionExpired
    case tgtNotFound
    case serviceTicketInvalid
    case missingSessionId
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "帳號或密碼錯誤"
        case .networkError(let error): return "網路錯誤: \(error.localizedDescription)"
        case .invalidResponse: return "伺服器回應無效"
        case .serverError(let message): return message
        case .sessionExpired: return "登入已過期，請重新登入"
        case .tgtNotFound: return "無法取得認證票證"
        case .serviceTicketInvalid: return "服務票證無效"
        case .missingSessionId: return "無法取得 Session ID"
        case .unknown: return "未知錯誤"
        }
    }
}
// MARK: - Todos Models

nonisolated struct TodosResponse: Codable, Sendable {
    let todo_list: [TodoItem]
}

nonisolated struct TodoItem: Codable, Sendable, Identifiable {
    let id: Int
    let title: String
    let type: TodoType
    let course_id: Int
    let course_code: String
    let course_name: String
    let course_type: Int
    let end_time: String
    let is_student: Bool
    let is_locked: Bool
    let prerequisites: [Prerequisite]
    let not_scored_num: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case course_id
        case course_code
        case course_name
        case course_type
        case end_time
        case is_student
        case is_locked
        case prerequisites
        case not_scored_num
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(TodoType.self, forKey: .type)
        course_id = try container.decode(Int.self, forKey: .course_id)
        course_code = try container.decode(String.self, forKey: .course_code)
        course_name = try container.decode(String.self, forKey: .course_name)
        course_type = try container.decode(Int.self, forKey: .course_type)
        end_time = try container.decode(String.self, forKey: .end_time)
        is_student = try container.decode(Bool.self, forKey: .is_student)
        is_locked = try container.decodeIfPresent(Bool.self, forKey: .is_locked) ?? false
        prerequisites = try container.decodeIfPresent([Prerequisite].self, forKey: .prerequisites) ?? []
        not_scored_num = try container.decodeIfPresent(Int.self, forKey: .not_scored_num)
    }
    
    var endDate: Date? {
        ISO8601DateFormatter().date(from: end_time)
    }
}

nonisolated enum TodoType: String, Codable, Sendable {
    case homework
    case exam
    case questionnaire
    
    var displayName: String {
        switch self {
        case .homework: return "作業"
        case .exam: return "考試"
        case .questionnaire: return "問卷"
        }
    }
}

nonisolated struct Prerequisite: Codable, Sendable {
    let activity_id: Int
    let activity_type: String
    let key: String
    let title: String
    let completion_criterion: CompletionCriterion
}

nonisolated struct CompletionCriterion: Codable, Sendable {
    let criterion_key: String
    let criterion_text: String
    let has_completed: Bool
    let completion_info: String
}

// MARK: - Course Outline Models

nonisolated struct TronClassMyCoursesRequest: Encodable, Sendable {
    let fields = "id,name,course_code"
    let page = 1
    let page_size = 100
    let conditions = Conditions()
    let showScorePassedStatus = false

    struct Conditions: Encodable, Sendable {
        let status = ["ongoing"]
        let keyword = ""
        let classify_type = "recently_started"
        let display_studio_list = false
    }
}

nonisolated struct TronClassMyCoursesResponse: Decodable, Sendable {
    let courses: [TronClassCourseSummary]
}

nonisolated struct TronClassCourseSummary: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let course_code: String
}

nonisolated struct TronClassCourseOutlineResponse: Decodable, Sendable {
    let id: Int
    let external_url: String?
    let status: String?
}

nonisolated struct OutlineAPIResponse<Result: Decodable>: Decodable {
    let statusCode: Int
    let result: Result
}

nonisolated struct OutlineCourseInfoAndBook: Decodable, Sendable {
    let jonCouSn: Int
    let cm: String?
    let book: String?
    let refBook: String?
    let norms: String?
    let other: String?
    let contact: String?
    let office: String?
    let courseOfficeHr: String?
    let dptObj: String?
}

nonisolated struct OutlineCourseCP: Decodable, Sendable {
    let jonCouSn: Int
    let couHr: Double?
    let atLeastWeekCnt: Int?
    let weeklyCP: [OutlineWeeklyCP]
}

nonisolated struct OutlineWeeklyCP: Decodable, Sendable {
    let cweek: Int
    let unit: String?
    let theme: String?
    let other: String?
    let physicalClassHr: Double?
    let asyncOnlineClassHr: Double?
    let syncOnlineClassHr: Double?
}

// MARK: - Enrollment Models

nonisolated struct EnrollmentsResponse: Decodable, Sendable {
    let enrollments: [Enrollment]
}

nonisolated struct Enrollment: Decodable, Sendable, Identifiable {
    let id: Int
    let roles: [String]
    let retake_status: Bool
    let seat_number: String
    let user: EnrollmentUser

    var primaryRole: EnrollmentRole {
        if roles.contains("instructor") { return .instructor }
        if roles.contains("instructor_assistant") { return .ta }
        return .student
    }
}

nonisolated enum EnrollmentRole: Sendable {
    case instructor
    case ta
    case student

    var displayName: String {
        switch self {
        case .instructor: return "教師"
        case .ta: return "助教"
        case .student: return "學生"
        }
    }
}

nonisolated struct EnrollmentUser: Decodable, Sendable {
    let id: Int
    let name: String
    let email: String
    let user_no: String
    let nickname: String?
    let grade: EnrollmentNamedRef?
    let klass: EnrollmentKlass?
    let department: EnrollmentDepartment?
    let org: EnrollmentNamedRef?
}

nonisolated struct EnrollmentNamedRef: Decodable, Sendable {
    let id: Int
    let name: String?
}

nonisolated struct EnrollmentKlass: Decodable, Sendable {
    let id: Int
    let name: String?
    let code: String?
}

nonisolated struct EnrollmentDepartment: Decodable, Sendable {
    let id: Int
    let name: String?
    let code: String?
}

nonisolated struct AvatarsResponse: Decodable, Sendable {
    let avatars: [String: String] // userId string → avatar URL string
}

nonisolated struct EnrollmentEnrollmentsRequest: Encodable, Sendable {
    let fields = "id,user(id,email,name,nickname,user_no,grade(id,name),klass(id,name,code),department(id,name,code),org(id,name)),roles,retake_status,seat_number"
}

// MARK: - Notification Models

nonisolated struct TronClassNotificationsResponse: Decodable, Sendable {
    let notifications: [TronClassRawNotification]
    let unread_count: Int?
}

/// Type-erased value for heterogeneous notification payload dictionaries.
nonisolated enum NotificationPayloadValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? container.decode(Int.self)    { self = .int(v);    return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        self = .null
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
}

/// Raw notification — payload decoded as an opaque dictionary to handle the
/// varying shapes across types (bulletin_created, exam_opened, topic_create, …).
nonisolated struct TronClassRawNotification: Decodable, Sendable, Identifiable {
    let id: String
    let type: String
    let top: Bool
    let timestamp: Int64
    let payload: [String: NotificationPayloadValue]

    /// Promotes to a typed value when `type == "bulletin_created"`.
    var asBulletin: TronClassNotification? {
        guard type == "bulletin_created" else { return nil }
        return TronClassNotification(
            id: id,
            top: top,
            timestamp: timestamp,
            bulletinTitle: payload["bulletin_title"]?.stringValue,
            bulletinContent: payload["bulletin_content"]?.stringValue,
            bulletinId: payload["bulletin_id"]?.intValue,
            courseId: payload["course_id"]?.intValue,
            courseName: payload["course_name"]?.stringValue,
            createdAt: payload["created_at"]?.stringValue
        )
    }
}

nonisolated struct TronClassNotification: Sendable, Identifiable {
    let id: String
    let top: Bool
    let timestamp: Int64
    let bulletinTitle: String?
    let bulletinContent: String?
    let bulletinId: Int?
    let courseId: Int?
    let courseName: String?
    let createdAt: String?

    var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }
}

// MARK: - TronClass API Errors

nonisolated enum TronClassAPIError: LocalizedError {
    case sessionExpired
    case unauthorized
    case invalidResponse
    case serverError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Session 已過期，請重新登入"
        case .unauthorized: return "未授權，請重新登入"
        case .invalidResponse: return "伺服器回應無效"
        case .serverError(let message): return message
        case .networkError(let error): return "網路錯誤: \(error.localizedDescription)"
        }
    }
}
