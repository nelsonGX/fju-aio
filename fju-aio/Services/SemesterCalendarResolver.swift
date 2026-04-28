import Foundation

struct SemesterNotificationWindow {
    let semester: String
    let startDate: Date?
    let endDate: Date?
    let source: String
}

enum SemesterCalendarResolver {
    static func notificationWindow(
        for semester: String,
        events: [CalendarEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SemesterNotificationWindow {
        guard let expectedWindow = estimatedWindow(for: semester, calendar: calendar) else {
            return fallbackWindow(for: semester, events: events, now: now)
        }

        let semesterEvents = events.filter {
            $0.startDate >= expectedWindow.start && $0.startDate <= expectedWindow.end
        }
        let classStart = semesterEvents
            .filter { isClassStart($0) }
            .map(\.startDate)
            .min()

        let lowerBound = classStart ?? max(now, expectedWindow.start)
        let flexibleWeekStart = semesterEvents
            .filter { isFlexibleLearningWeek($0) && $0.startDate > lowerBound }
            .map(\.startDate)
            .min()

        return SemesterNotificationWindow(
            semester: semester,
            startDate: classStart,
            endDate: flexibleWeekStart ?? expectedWindow.end,
            source: flexibleWeekStart == nil ? "estimated-end" : "calendar"
        )
    }

    private static func fallbackWindow(
        for semester: String,
        events: [CalendarEvent],
        now: Date
    ) -> SemesterNotificationWindow {
        let futureClassStart = events
            .filter { isClassStart($0) && $0.startDate > now }
            .map(\.startDate)
            .min()
        let lowerBound = futureClassStart ?? now
        let flexibleWeekStart = events
            .filter { isFlexibleLearningWeek($0) && $0.startDate > lowerBound }
            .map(\.startDate)
            .min()

        return SemesterNotificationWindow(
            semester: semester,
            startDate: futureClassStart,
            endDate: flexibleWeekStart,
            source: flexibleWeekStart == nil ? "unresolved" : "calendar-fallback"
        )
    }

    private static func estimatedWindow(
        for semester: String,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let parts = semester.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }

        let academicStartYear = parts[0] + 1911
        var start = DateComponents()
        start.calendar = calendar
        start.timeZone = calendar.timeZone
        start.hour = 0
        start.minute = 0
        start.second = 0

        var end = DateComponents()
        end.calendar = calendar
        end.timeZone = calendar.timeZone
        end.hour = 23
        end.minute = 59
        end.second = 59

        if parts[1] == 1 {
            start.year = academicStartYear
            start.month = 8
            start.day = 1
            end.year = academicStartYear + 1
            end.month = 1
            end.day = 31
        } else {
            start.year = academicStartYear + 1
            start.month = 2
            start.day = 1
            end.year = academicStartYear + 1
            end.month = 7
            end.day = 31
        }

        guard let startDate = calendar.date(from: start),
              let endDate = calendar.date(from: end) else { return nil }
        return (startDate, endDate)
    }

    private static func isClassStart(_ event: CalendarEvent) -> Bool {
        event.title.localizedStandardContains("開始上課日")
    }

    private static func isFlexibleLearningWeek(_ event: CalendarEvent) -> Bool {
        event.title.localizedStandardContains("彈性多元學習週")
    }
}
