import Foundation

struct Rollcall: Identifiable, Codable, Sendable {
    let rollcall_id: Int
    let course_id: Int
    let course_title: String
    let rollcall_status: String   // "in_progress", "on_call", "late"
    let source: String             // "number", "radar"
    let is_number: Bool
    let is_radar: Bool
    let is_expired: Bool
    let status: String             // student status: "absent", "on_call", "late"
    let rollcall_time: String
    let title: String
    let created_by_name: String
    let student_rollcall_id: Int

    var id: Int { rollcall_id }
    var isActive: Bool { rollcall_status == "in_progress" && !is_expired }
    var isAlreadyCheckedIn: Bool { status == "on_call" || status == "late" }
}

struct RollcallsResponse: Codable {
    let rollcalls: [Rollcall]
}

enum RollcallCheckInResult {
    case success(String)
    case failure(String)
}

enum RollcallError: LocalizedError {
    case sessionExpired
    case wrongCode

    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "登入已過期，請重新登入"
        case .wrongCode:      return "數字碼錯誤，請再試一次"
        }
    }
}
