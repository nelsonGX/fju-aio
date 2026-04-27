import Foundation

// MARK: - Authentication Models

struct TronClassSession: Codable, Sendable {
    let sessionId: String
    let userId: Int
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
}

struct CASLoginResponse: Codable, Sendable {
    let user_id: Int
}

// MARK: - Authentication Errors

enum AuthenticationError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case invalidResponse
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
        case .sessionExpired: return "登入已過期，請重新登入"
        case .tgtNotFound: return "無法取得認證票證"
        case .serviceTicketInvalid: return "服務票證無效"
        case .missingSessionId: return "無法取得 Session ID"
        case .unknown: return "未知錯誤"
        }
    }
}
// MARK: - Todos Models

struct TodosResponse: Codable, Sendable {
    let todo_list: [TodoItem]
}

struct TodoItem: Codable, Sendable, Identifiable {
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

enum TodoType: String, Codable, Sendable {
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

struct Prerequisite: Codable, Sendable {
    let activity_id: Int
    let activity_type: String
    let key: String
    let title: String
    let completion_criterion: CompletionCriterion
}

struct CompletionCriterion: Codable, Sendable {
    let criterion_key: String
    let criterion_text: String
    let has_completed: Bool
    let completion_info: String
}

// MARK: - TronClass API Errors

enum TronClassAPIError: LocalizedError {
    case sessionExpired
    case unauthorized
    case invalidResponse
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Session 已過期，請重新登入"
        case .unauthorized: return "未授權，請重新登入"
        case .invalidResponse: return "伺服器回應無效"
        case .networkError(let error): return "網路錯誤: \(error.localizedDescription)"
        }
    }
}
