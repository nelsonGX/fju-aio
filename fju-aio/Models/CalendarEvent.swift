import Foundation

struct CalendarEvent: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date?
    let category: EventCategory
    let description: String?

    enum EventCategory: String, CaseIterable, Codable, Sendable {
        case exam = "考試"
        case holiday = "假日"
        case registration = "註冊"
        case activity = "活動"
        case deadline = "截止日"
    }
}
