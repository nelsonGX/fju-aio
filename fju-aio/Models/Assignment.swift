import Foundation

struct Assignment: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let courseName: String
    let dueDate: Date
    let description: String?
    let source: AssignmentSource

    enum AssignmentSource: String, Codable, Sendable {
        case tronclass = "TronClass"
        case manual = "手動新增"
    }
}
