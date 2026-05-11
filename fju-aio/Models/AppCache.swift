import Foundation

/// Memory cache backed by disk so academic data can be shown immediately after
/// app restart, then refreshed by the caller.
@MainActor
final class AppCache {
    static let shared = AppCache()
    private let disk = PersistentDiskCache.shared
    private let schemaVersion = 1

    private init() {
        semesters = disk.load([String].self, key: Keys.semesters, schemaVersion: schemaVersion).map {
            (data: $0.value, cachedAt: $0.cachedAt)
        }
    }

    // MARK: - Courses
    private var courses: [String: (data: [Course], cachedAt: Date)] = [:]
    private var semesters: (data: [String], cachedAt: Date)?

    func getCourses(semester: String) -> [Course]? {
        if let entry = courses[semester] { return entry.data }
        guard let entry = disk.load([Course].self, key: Keys.courses(semester), schemaVersion: schemaVersion) else { return nil }
        courses[semester] = (entry.value, entry.cachedAt)
        return entry.value
    }

    func setCourses(_ data: [Course], semester: String) {
        courses[semester] = (data, Date())
        disk.save(data, key: Keys.courses(semester), schemaVersion: schemaVersion)
    }

    func getSemesters() -> [String]? { semesters?.data }
    func setSemesters(_ data: [String]) {
        semesters = (data, Date())
        disk.save(data, key: Keys.semesters, schemaVersion: schemaVersion)
    }

    // MARK: - Grades
    private var grades: [String: (data: [Grade], cachedAt: Date)] = [:]
    private var gpaSummaries: [String: (data: GPASummary, cachedAt: Date)] = [:]

    func getGrades(semester: String) -> [Grade]? {
        if let entry = grades[semester] { return entry.data }
        guard let entry = disk.load([Grade].self, key: Keys.grades(semester), schemaVersion: schemaVersion) else { return nil }
        grades[semester] = (entry.value, entry.cachedAt)
        return entry.value
    }

    func setGrades(_ data: [Grade], semester: String) {
        grades[semester] = (data, Date())
        disk.save(data, key: Keys.grades(semester), schemaVersion: schemaVersion)
    }

    func getGPASummary(semester: String) -> GPASummary? {
        if let entry = gpaSummaries[semester] { return entry.data }
        guard let entry = disk.load(GPASummary.self, key: Keys.gpa(semester), schemaVersion: schemaVersion) else { return nil }
        gpaSummaries[semester] = (entry.value, entry.cachedAt)
        return entry.value
    }

    func setGPASummary(_ data: GPASummary, semester: String) {
        gpaSummaries[semester] = (data, Date())
        disk.save(data, key: Keys.gpa(semester), schemaVersion: schemaVersion)
    }

    // MARK: - Assignments
    private var assignments: (data: [Assignment], cachedAt: Date)?

    func getAssignments() -> [Assignment]? {
        if let assignments { return assignments.data }
        guard let entry = disk.load([Assignment].self, key: Keys.assignments, schemaVersion: schemaVersion) else { return nil }
        assignments = (entry.value, entry.cachedAt)
        return entry.value
    }

    func setAssignments(_ data: [Assignment]) {
        assignments = (data, Date())
        disk.save(data, key: Keys.assignments, schemaVersion: schemaVersion)
    }

    // MARK: - Attendance
    private var attendance: [String: (data: [AttendanceRecord], cachedAt: Date)] = [:]

    func getAttendance(semester: String) -> [AttendanceRecord]? {
        if let entry = attendance[semester] { return entry.data }
        guard let entry = disk.load([AttendanceRecord].self, key: Keys.attendance(semester), schemaVersion: schemaVersion) else { return nil }
        attendance[semester] = (entry.value, entry.cachedAt)
        return entry.value
    }

    func setAttendance(_ data: [AttendanceRecord], semester: String) {
        attendance[semester] = (data, Date())
        disk.save(data, key: Keys.attendance(semester), schemaVersion: schemaVersion)
    }

    // MARK: - Calendar
    private var calendarEvents: [String: (data: [CalendarEvent], cachedAt: Date)] = [:]

    func getCalendarEvents(semester: String) -> [CalendarEvent]? {
        if let entry = calendarEvents[semester] { return entry.data }
        guard let entry = disk.load([CalendarEvent].self, key: Keys.calendar(semester), schemaVersion: schemaVersion) else { return nil }
        calendarEvents[semester] = (entry.value, entry.cachedAt)
        return entry.value
    }

    func setCalendarEvents(_ data: [CalendarEvent], semester: String) {
        calendarEvents[semester] = (data, Date())
        disk.save(data, key: Keys.calendar(semester), schemaVersion: schemaVersion)
    }

    // MARK: - Search Helpers

    /// Returns all courses across all cached semesters (deduplicated by course id).
    func allCachedCourses() -> [Course] {
        if let semesters = getSemesters() {
            for semester in semesters {
                _ = getCourses(semester: semester)
            }
        }

        var seen = Set<String>()
        return courses.values.flatMap(\.data).filter { seen.insert($0.id).inserted }
    }

    /// Returns all calendar events across all cached semesters (deduplicated by event id).
    func allCachedCalendarEvents() -> [CalendarEvent] {
        if let semesters = getSemesters() {
            for semester in semesters {
                _ = getCalendarEvents(semester: semester)
            }
        }

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
        disk.removeAll()
    }

    private enum Keys {
        static let semesters = "semesters"
        static let assignments = "assignments"

        static func courses(_ semester: String) -> String { "courses.\(semester)" }
        static func grades(_ semester: String) -> String { "grades.\(semester)" }
        static func gpa(_ semester: String) -> String { "gpa.\(semester)" }
        static func attendance(_ semester: String) -> String { "attendance.\(semester)" }
        static func calendar(_ semester: String) -> String { "calendar.\(semester)" }
    }
}
