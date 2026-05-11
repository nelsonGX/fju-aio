import Foundation

// MARK: - Attendance Rollcall (per-course history)

nonisolated struct AttendanceRollcall: Identifiable, Codable, Sendable {
    let rollcall_id: Int
    let title: String
    let rollcall_time: String
    let rollcall_status: String
    let status: String
    let student_status: String
    let student_status_detail: String
    let source: String
    let type: String
    let is_number: Bool
    let is_radar: Bool
    let is_expired: Bool
    let scored: Bool
    let student_rollcall_id: Int
    let published_at: String?

    var id: Int { rollcall_id }

    var rollcallDate: Date? {
        ISO8601DateFormatter().date(from: rollcall_time)
    }

    /// Non-empty when status == "on_leave"; contains the leave type e.g. "病假", "事假"
    var leaveReason: String? {
        let detail = student_status_detail.trimmingCharacters(in: .whitespaces)
        return detail.isEmpty ? nil : detail
    }

    /// True when this record is any kind of approved leave (on_sick_leave, on_personal_leave, etc.)
    var isLeave: Bool {
        status.hasSuffix("_leave") && status != "on_public_leave"
    }

    var attendanceStatus: AttendanceRecord.AttendanceStatus {
        switch status {
        case "absent": return .absent
        case "on_call_fine", "on_call": return .present
        case "late", "on_call_arrive_late": return .late
        case "on_public_leave": return .publicLeave
        default:
            if isLeave { return .leave }
            return .other
        }
    }
}

nonisolated struct AttendanceRollcallsResponse: Codable, Sendable {
    let rollcalls: [AttendanceRollcall]
}

// MARK: - Active Rollcall (check-in)

nonisolated struct Rollcall: Identifiable, Codable, Sendable {
    let rollcall_id: Int
    let course_id: Int?
    let course_title: String
    let rollcall_status: String   // "in_progress", "on_call", "late"
    let source: String?            // "number", "radar", "qr"
    let is_number: Bool
    let is_radar: Bool
    let is_qr: Bool?
    let is_expired: Bool
    let status: String             // student status: "absent", "on_call_fine", "on_call", "late"
    let rollcall_time: String
    let title: String
    let created_by_name: String?
    let student_rollcall_id: Int?

    var id: Int { rollcall_id }

    /// True if this is a QR rollcall — prefer the explicit flag, fall back to source field.
    var isQR: Bool { is_qr ?? (source == "qr") }
    var isNumber: Bool { is_number || source == "number" }
    var isRadar: Bool { is_radar || source == "radar" }

    var isActive: Bool { rollcall_status == "in_progress" && !is_expired }
    var isAlreadyCheckedIn: Bool { status == "on_call_fine" || status == "on_call" || status == "late" }
}

nonisolated struct RollcallsResponse: Codable, Sendable {
    let rollcalls: [Rollcall]
}

enum RollcallCheckInResult {
    case success(String?)   // code for number rollcall; nil for radar
    case failure(String)
}

/// Per-friend result shown in the group check-in status log.
enum FriendCheckInStatus: Sendable {
    case success
    case authFailed
    case notEnrolled
    case checkInFailed(String)
}

enum RollcallError: LocalizedError {
    case sessionExpired
    case wrongCode
    case invalidQRCode
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:  return "登入已過期，請重新登入"
        case .wrongCode:       return "數字碼錯誤，請再試一次"
        case .invalidQRCode:   return "無效的 QR Code，請重新掃描"
        case .serverMessage(let message): return message
        }
    }
}
