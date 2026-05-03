import Foundation

/// In-memory cache that persists for the lifetime of the app session.
/// Data is keyed by a string and stored alongside a timestamp.
/// On the next app launch the cache starts empty, so stale data is never shown.
@MainActor
final class AppCache {
    static let shared = AppCache()
    private init() {}

    // MARK: - Courses
    private var courses: [String: (data: [Course], cachedAt: Date)] = [:]
    private var semesters: (data: [String], cachedAt: Date)?

    func getCourses(semester: String) -> [Course]? { courses[semester]?.data }
    func setCourses(_ data: [Course], semester: String) { courses[semester] = (data, Date()) }

    func getSemesters() -> [String]? { semesters?.data }
    func setSemesters(_ data: [String]) { semesters = (data, Date()) }

    // MARK: - Grades
    private var grades: [String: (data: [Grade], cachedAt: Date)] = [:]
    private var gpaSummaries: [String: (data: GPASummary, cachedAt: Date)] = [:]

    func getGrades(semester: String) -> [Grade]? { grades[semester]?.data }
    func setGrades(_ data: [Grade], semester: String) { grades[semester] = (data, Date()) }

    func getGPASummary(semester: String) -> GPASummary? { gpaSummaries[semester]?.data }
    func setGPASummary(_ data: GPASummary, semester: String) { gpaSummaries[semester] = (data, Date()) }

    // MARK: - Assignments
    private var assignments: (data: [Assignment], cachedAt: Date)?

    func getAssignments() -> [Assignment]? { assignments?.data }
    func setAssignments(_ data: [Assignment]) { assignments = (data, Date()) }

    // MARK: - Attendance
    private var attendance: [String: (data: [AttendanceRecord], cachedAt: Date)] = [:]

    func getAttendance(semester: String) -> [AttendanceRecord]? { attendance[semester]?.data }
    func setAttendance(_ data: [AttendanceRecord], semester: String) { attendance[semester] = (data, Date()) }

    // MARK: - Calendar
    private var calendarEvents: [String: (data: [CalendarEvent], cachedAt: Date)] = [:]

    func getCalendarEvents(semester: String) -> [CalendarEvent]? { calendarEvents[semester]?.data }
    func setCalendarEvents(_ data: [CalendarEvent], semester: String) { calendarEvents[semester] = (data, Date()) }

    // MARK: - Search Helpers

    /// Returns all courses across all cached semesters (deduplicated by course id).
    func allCachedCourses() -> [Course] {
        var seen = Set<String>()
        return courses.values.flatMap(\.data).filter { seen.insert($0.id).inserted }
    }

    /// Returns all calendar events across all cached semesters (deduplicated by event id).
    func allCachedCalendarEvents() -> [CalendarEvent] {
        var seen = Set<String>()
        return calendarEvents.values.flatMap(\.data).filter { seen.insert($0.id).inserted }
    }

    // MARK: - Invalidation
    func invalidateAll() {
        courses = [:]
        semesters = nil
        grades = [:]
        gpaSummaries = [:]
        assignments = nil
        attendance = [:]
        calendarEvents = [:]
    }
}
