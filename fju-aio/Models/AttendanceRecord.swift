import Foundation

struct AttendanceRecord: Identifiable {
    let id: String
    let courseName: String
    let date: Date
    let period: Int
    let status: AttendanceStatus
    let rollcallTitle: String
    let source: String  // "qr", "radar", "number"

    enum AttendanceStatus: String, CaseIterable {
        case present = "出席"
        case absent = "缺席"
        case late = "遲到"
        case excused = "請假"
    }
}
