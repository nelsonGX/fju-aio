import Foundation

struct AttendanceRecord: Identifiable, Codable, Sendable {
    let id: String
    let courseName: String
    let date: Date
    let period: Int
    let status: AttendanceStatus
    let rollcallTitle: String
    let source: String  // "qr", "radar", "number"

    enum AttendanceStatus: String, CaseIterable, Codable, Sendable {
        case present = "出席"
        case absent = "缺席"
        case late = "遲到"
        case excused = "請假"
        case publicLeave = "公假"
        case leave = "假"      // on_leave — reason stored in student_status_detail
        case other = "其他"
    }
}
