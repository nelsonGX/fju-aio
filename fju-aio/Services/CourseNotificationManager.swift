import Foundation
import ActivityKit
import Observation
import UIKit

// MARK: - Server config

private let serverBaseURL = "https://fju-aio-notify.appppple.com"
private let serverAuthToken: String? = nil
private let liveActivityDismissalDelay: TimeInterval = 30

@Observable
final class CourseNotificationManager {
    static let shared = CourseNotificationManager()

    private init() {
        observePushToStartTokens()
        observeActivityUpdates()
    }

    // MARK: - Persisted Preferences

    /// Master switch for Live Activities.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.enabled)
            if !newValue {
                Task {
                    await endAllLiveActivities()
                    await cancelRemoteSchedules(deactivateToken: true)
                }
            }
        }
    }

    /// Whether to start a Live Activity when class is about to begin.
    var notifyBefore: Bool {
        get { UserDefaults.standard.object(forKey: Keys.notifyBefore) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.notifyBefore) }
    }

    /// Whether to show the Live Activity during class.
    var notifyStart: Bool {
        get { UserDefaults.standard.object(forKey: Keys.notifyStart) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.notifyStart) }
    }

    /// Whether to keep the Live Activity running until end of class.
    var notifyEnd: Bool {
        get { UserDefaults.standard.object(forKey: Keys.notifyEnd) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.notifyEnd) }
    }

    /// Minutes before class start to show the Live Activity.
    var minutesBefore: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.minutesBefore)
            return v == 0 ? 15 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.minutesBefore) }
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let enabled       = "courseNotificationsEnabled"
        static let notifyBefore  = "courseNotifyBefore"
        static let notifyStart   = "courseNotifyStart"
        static let notifyEnd     = "courseNotifyEnd"
        static let minutesBefore = "courseNotificationMinutesBefore"
    }

    // MARK: - Called after course load

    /// Starts a Live Activity if a class is active or about to start today.
    func scheduleAll(
        for courses: [Course],
        semesterStartDate overrideSemesterStartDate: Date? = nil,
        semesterEndDate overrideSemesterEndDate: Date? = nil
    ) async {
        guard isEnabled, notifyStart || notifyBefore else { return }
        lastCourseSnapshot = courses
        await scheduleRemoteCourseActivities(
            for: courses,
            semesterStartDate: overrideSemesterStartDate,
            semesterEndDate: overrideSemesterEndDate
        )
        await startLiveActivityIfNeeded(for: courses)
    }

    // MARK: - Live Activity

    @discardableResult
    @MainActor
    func startLiveActivity(for course: Course) async -> Bool {
        guard isEnabled else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[CourseNotification] Live Activities 未啟用")
            return false
        }

        let now = Date()
        let calendar = Calendar.current
        guard let startDate = courseDate(for: course, on: now, calendar: calendar, useEndTime: false),
              let endDate   = courseDate(for: course, on: now, calendar: calendar, useEndTime: true) else {
            print("[CourseNotification] 無法計算課程時間")
            return false
        }

        let phase: CoursePhase
        if now < startDate      { phase = .before }
        else if now < endDate   { phase = .during }
        else {
            print("[CourseNotification] 課程已結束，跳過 Live Activity")
            return false
        }
        guard phase != .before || notifyBefore else { return false }
        guard phase != .during || notifyStart else { return false }

        let attributes = CourseActivityAttributes(
            courseName: course.name,
            courseId: course.id,
            location: course.location,
            instructor: course.instructor
        )
        let state = CourseActivityAttributes.ContentState(
            phase: phase,
            classStartDate: startDate,
            classEndDate: endDate
        )
        let content = ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60))

        if let existingActivity = runningActivity(for: course) {
            activeActivityIDs[course.id] = existingActivity.id
            await existingActivity.update(content)
            scheduleLocalPhaseUpdates(for: existingActivity, state: state)
            print("[CourseNotification] ✅ Live Activity 已存在，更新而非重新啟動: \(existingActivity.id) phase=\(phase.rawValue)")
            return await registerActivity(existingActivity, courseId: course.id, startDate: startDate, endDate: endDate)
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            print("[CourseNotification] ✅ Live Activity 啟動: \(activity.id) phase=\(phase.rawValue)")
            activeActivityIDs[course.id] = activity.id

            return await registerActivity(activity, courseId: course.id, startDate: startDate, endDate: endDate)
        } catch {
            print("[CourseNotification] ❌ Live Activity 啟動失敗: \(error)")
            return false
        }
    }

    @MainActor
    func updateLiveActivity(for course: Course) async {
        guard let activity = runningActivity(for: course) else { return }

        let now = Date()
        let calendar = Calendar.current
        guard let startDate = courseDate(for: course, on: now, calendar: calendar, useEndTime: false),
              let endDate   = courseDate(for: course, on: now, calendar: calendar, useEndTime: true) else { return }

        let phase: CoursePhase
        if now < startDate      { phase = .before }
        else if now < endDate   { phase = .during }
        else                    { phase = .ended }

        let newState = CourseActivityAttributes.ContentState(
            phase: phase,
            classStartDate: startDate,
            classEndDate: endDate
        )
        let content = ActivityContent(state: newState, staleDate: endDate.addingTimeInterval(120))
        await activity.update(content)
        print("[CourseNotification] ✅ Live Activity 更新: phase=\(phase.rawValue)")
    }

    @MainActor
    func endLiveActivity(for course: Course) async {
        guard let activity = runningActivity(for: course) else { return }
        let activityId = activity.id

        let finalState = CourseActivityAttributes.ContentState(
            phase: .ended,
            classStartDate: Date(),
            classEndDate: Date()
        )
        let content = ActivityContent(state: finalState, staleDate: Date().addingTimeInterval(60))
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60)))
        activeActivityIDs.removeValue(forKey: course.id)
        print("[CourseNotification] ✅ Live Activity 結束: \(course.name)")

        // Notify server to stop sending pushes for this activity
        Task {
            await unregisterActivity(id: activityId)
        }
    }

    @MainActor
    func endAllLiveActivities() async {
        for activity in Activity<CourseActivityAttributes>.activities {
            let activityId = activity.id
            await activity.end(activity.content, dismissalPolicy: .immediate)
            Task {
                await unregisterActivity(id: activityId)
            }
        }
        activeActivityIDs.removeAll()
        print("[CourseNotification] ✅ 全部 Live Activities 結束")
    }

    func cancelForLogout() async {
        await endAllLiveActivities()
        await cancelRemoteSchedules(deactivateToken: true)
    }

    // MARK: - Test helpers (DebugView)

    /// Schedules a "during" Live Activity to start after `delaySeconds`.
    /// Call this, kill the app, wait — the server should push the update.
    @discardableResult
    @MainActor
    func scheduleDelayedTestLiveActivity(course: Course, delaySeconds: TimeInterval) async -> Bool {
        await endAllLiveActivities()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[CourseNotification] Live Activities 未啟用")
            return false
        }

        let now = Date()
        let startDate = now.addingTimeInterval(delaySeconds)
        let endDate   = startDate.addingTimeInterval(90 * 60) // 90-min class

        let attributes = CourseActivityAttributes(
            courseName: course.name,
            courseId: course.id,
            location: course.location,
            instructor: course.instructor
        )
        // Start in .before phase now; the server will push .during at startDate
        let state = CourseActivityAttributes.ContentState(
            phase: .before,
            classStartDate: startDate,
            classEndDate: endDate
        )
        let content = ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60))
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            print("[CourseNotification] ✅ 延遲測試 Live Activity 啟動: \(activity.id), 上課時間: \(startDate)")
            return await registerActivity(activity, courseId: course.id, startDate: startDate, endDate: endDate)
        } catch {
            print("[CourseNotification] ❌ 延遲測試 Live Activity 失敗: \(error)")
            return false
        }
    }

    /// Runs a server-driven test cycle: 30s hidden, 30s before, 30s during, then ended.
    @discardableResult
    @MainActor
    func scheduleFullCycleTestLiveActivity(course: Course) async -> Bool {
        await endAllLiveActivities()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[CourseNotification] Live Activities 未啟用")
            return false
        }

        print("[CourseNotification] 完整週期測試：30 秒後啟動 Live Activity")
        try? await Task.sleep(nanoseconds: 30_000_000_000)

        let now = Date()
        let startDate = now.addingTimeInterval(30)
        let endDate = startDate.addingTimeInterval(30)

        let attributes = CourseActivityAttributes(
            courseName: course.name,
            courseId: course.id,
            location: course.location,
            instructor: course.instructor
        )
        let state = CourseActivityAttributes.ContentState(
            phase: .before,
            classStartDate: startDate,
            classEndDate: endDate
        )
        let content = ActivityContent(state: state, staleDate: endDate.addingTimeInterval(90))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            print("[CourseNotification] ✅ 完整週期測試 Live Activity 啟動: \(activity.id), start=\(startDate), end=\(endDate)")
            return await registerActivity(activity, courseId: course.id, startDate: startDate, endDate: endDate)
        } catch {
            print("[CourseNotification] ❌ 完整週期測試 Live Activity 失敗: \(error)")
            return false
        }
    }

    @discardableResult
    @MainActor
    func fireTestLiveActivity(course: Course, phase: CoursePhase) async -> Bool {
        await endAllLiveActivities()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[CourseNotification] Live Activities 未啟用")
            return false
        }

        let now = Date()
        let attributes = CourseActivityAttributes(
            courseName: course.name,
            courseId: course.id,
            location: course.location,
            instructor: course.instructor
        )
        let startDate: Date
        let endDate: Date
        switch phase {
        case .before:
            startDate = now.addingTimeInterval(Double(minutesBefore) * 60)
            endDate   = startDate.addingTimeInterval(100 * 60)
        case .during:
            startDate = now.addingTimeInterval(-30 * 60)
            endDate   = now.addingTimeInterval(20 * 60)
        case .ended:
            startDate = now.addingTimeInterval(-100 * 60)
            endDate   = now.addingTimeInterval(-1)
        }
        let state = CourseActivityAttributes.ContentState(
            phase: phase,
            classStartDate: startDate,
            classEndDate: endDate
        )
        let content = ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60))
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            print("[CourseNotification] ✅ 測試 Live Activity: \(activity.id) phase=\(phase.rawValue)")
            return await registerActivity(activity, courseId: course.id, startDate: startDate, endDate: endDate)
        } catch {
            print("[CourseNotification] ❌ 測試 Live Activity 失敗: \(error)")
            return false
        }
    }

    // MARK: - Private helpers

    private var activeActivityIDs: [String: String] = [:]
    private var lastCourseSnapshot: [Course] = []

    private func runningActivity(for course: Course) -> Activity<CourseActivityAttributes>? {
        Activity<CourseActivityAttributes>.activities.first {
            activeActivityIDs[course.id] == $0.id || $0.attributes.courseName == course.name
        }
    }

    @MainActor
    private func startLiveActivityIfNeeded(for courses: [Course]) async {
        let now = Date()
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: now)

        for course in courses {
            guard course.dayOfWeekNumber == weekdayToCourseDay(todayWeekday) else { continue }
            guard let startDate = courseDate(for: course, on: now, calendar: calendar, useEndTime: false),
                  let endDate   = courseDate(for: course, on: now, calendar: calendar, useEndTime: true) else { continue }
            let windowStart = notifyBefore
                ? startDate.addingTimeInterval(-Double(minutesBefore) * 60)
                : startDate
            if now >= windowStart && now < endDate {
                let started = await startLiveActivity(for: course)
                if started { break }
            }
        }
    }

    private func scheduleRemoteCourseActivities(
        for courses: [Course],
        semesterStartDate overrideSemesterStartDate: Date?,
        semesterEndDate overrideSemesterEndDate: Date?
    ) async {
        let now = Date()
        let identity = await notificationIdentity()
        let semester = semesterIdentifier(from: courses)
        let semesterStartDate = overrideSemesterStartDate ?? now
        let semesterEndDate = overrideSemesterEndDate ?? estimatedSemesterEndDate(for: semester, from: now)
        guard semesterEndDate > now else {
            print("[CourseNotification] 學期已結束，跳過伺服器排程 semester=\(semester), until=\(semesterEndDate)")
            await cancelRemoteSchedules(semester: semester, deactivateToken: false)
            return
        }
        print("[CourseNotification] 同步課程排程 semester=\(semester), courses=\(courses.count), from=\(semesterStartDate), until=\(semesterEndDate)")
        let schedules = Array(courses.flatMap {
            remoteSchedules(for: $0, from: now, semesterStartDate: semesterStartDate, until: semesterEndDate, identity: identity)
        }.prefix(1000))

        guard !schedules.isEmpty else {
            print("[CourseNotification] 沒有需要伺服器排程的課程 Live Activity")
            return
        }

        let payload = PushToStartSemesterSyncPayload(
            userId: identity.userId,
            deviceId: identity.deviceId,
            semester: semester,
            semesterEndDate: unixSeconds(semesterEndDate),
            schedules: schedules
        )
        await MainActor.run { SyncStatusManager.shared.begin("正在同步課程通知排程…") }
        let success = await postJSON(to: "\(serverBaseURL)/push-to-start/sync-semester", body: payload)
        await MainActor.run { SyncStatusManager.shared.end() }
        if success {
            print("[CourseNotification] ✅ 已向伺服器同步整學期 Live Activities: \(semester) \(schedules.count)")
        } else {
            print("[CourseNotification] ⚠️ 課程 Live Activity 伺服器排程失敗")
        }
    }

    private func remoteSchedules(
        for course: Course,
        from now: Date,
        semesterStartDate: Date,
        until semesterEndDate: Date,
        identity: NotificationIdentity
    ) -> [RemoteCourseActivitySchedule] {
        let showBefore = notifyBefore
        let showDuring = notifyStart
        guard showBefore || showDuring else { return [] }

        return courseOccurrences(for: course, from: now, semesterStartDate: semesterStartDate, until: semesterEndDate).compactMap { occurrence in
            let pushDate = showBefore
                ? occurrence.startDate.addingTimeInterval(-Double(minutesBefore) * 60)
                : occurrence.startDate
            let initialPhase: CoursePhase = showBefore ? .before : .during
            let endTransitionDate = showDuring ? occurrence.endDate : occurrence.startDate
            let dismissalDate = notifyEnd && showDuring
                ? occurrence.endDate.addingTimeInterval(liveActivityDismissalDelay)
                : endTransitionDate

            guard pushDate.timeIntervalSince(now) > 5 else { return nil }
            guard dismissalDate.timeIntervalSince(now) > 5 else { return nil }

            return RemoteCourseActivitySchedule(
                userId: identity.userId,
                deviceId: identity.deviceId,
                courseName: course.name,
                courseId: course.id,
                location: course.location,
                instructor: course.instructor,
                pushAt: unixSeconds(pushDate),
                classStartDate: unixSeconds(occurrence.startDate),
                classEndDate: unixSeconds(occurrence.endDate),
                initialPhase: initialPhase,
                endAt: unixSeconds(endTransitionDate),
                dismissalDate: unixSeconds(dismissalDate)
            )
        }
    }

    private func nextOccurrence(for course: Course, from now: Date) -> (startDate: Date, endDate: Date)? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0...7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            guard course.dayOfWeekNumber == weekdayToCourseDay(weekday),
                  let startDate = courseDate(for: course, on: date, calendar: calendar, useEndTime: false),
                  let endDate = courseDate(for: course, on: date, calendar: calendar, useEndTime: true),
                  endDate > startDate else { continue }

            let activeUntil = notifyStart
                ? (notifyEnd ? endDate.addingTimeInterval(liveActivityDismissalDelay) : endDate)
                : startDate
            if activeUntil.timeIntervalSince(now) > 5 {
                return (startDate, endDate)
            }
        }

        return nil
    }

    private func courseOccurrences(
        for course: Course,
        from now: Date,
        semesterStartDate: Date,
        until semesterEndDate: Date
    ) -> [(startDate: Date, endDate: Date)] {
        let calendar = Calendar.current
        var occurrences: [(startDate: Date, endDate: Date)] = []
        var date = calendar.startOfDay(for: max(now, semesterStartDate))
        let finalDate = calendar.startOfDay(for: semesterEndDate)

        while date < finalDate {
            let weekday = calendar.component(.weekday, from: date)
            if course.dayOfWeekNumber == weekdayToCourseDay(weekday),
               shouldInclude(course: course, on: date, calendar: calendar),
               let startDate = courseDate(for: course, on: date, calendar: calendar, useEndTime: false),
               let endDate = courseDate(for: course, on: date, calendar: calendar, useEndTime: true),
               endDate > startDate,
               startDate < semesterEndDate {
                occurrences.append((startDate, endDate))
            }

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return occurrences
    }

    private func shouldInclude(course: Course, on date: Date, calendar: Calendar) -> Bool {
        switch course.weeks {
        case "單":
            return calendar.component(.weekOfYear, from: date).isMultiple(of: 2) == false
        case "雙":
            return calendar.component(.weekOfYear, from: date).isMultiple(of: 2)
        default:
            return true
        }
    }

    private func semesterIdentifier(from courses: [Course]) -> String {
        courses.first { !$0.semester.isEmpty }?.semester ?? "unknown"
    }

    private func estimatedSemesterEndDate(for semester: String, from now: Date) -> Date {
        let calendar = Calendar.current
        let parts = semester.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else {
            return calendar.date(byAdding: .day, value: 120, to: now) ?? now.addingTimeInterval(120 * 24 * 60 * 60)
        }

        let gregorianStartYear = parts[0] + 1911
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.hour = 23
        comps.minute = 59
        comps.second = 59

        if parts[1] == 1 {
            comps.year = gregorianStartYear + 1
            comps.month = 1
            comps.day = 31
        } else {
            comps.year = gregorianStartYear + 1
            comps.month = 7
            comps.day = 31
        }

        let estimated = calendar.date(from: comps) ?? now
        return estimated
    }

    private func courseDate(for course: Course, on referenceDate: Date, calendar: Calendar, useEndTime: Bool) -> Date? {
        let period = useEndTime ? course.endPeriod : course.startPeriod
        guard period >= 1, period <= FJUPeriod.periodTimes.count else { return nil }
        let timeString = useEndTime ? FJUPeriod.periodTimes[period - 1].end : FJUPeriod.periodTimes[period - 1].start
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        comps.hour = parts[0]; comps.minute = parts[1]; comps.second = 0
        return calendar.date(from: comps)
    }

    private func weekdayToCourseDay(_ weekday: Int) -> Int {
        switch weekday {
        case 2: return 1; case 3: return 2; case 4: return 3
        case 5: return 4; case 6: return 5; case 7: return 6
        case 1: return 7; default: return 0
        }
    }

    // MARK: - Server registration

    private struct ActivityRegistrationPayload: Encodable {
        let userId: String
        let deviceId: String
        let activityId: String
        let pushToken: String
        let courseName: String
        let courseId: String
        let classStartDate: Int
        let classEndDate: Int
    }

    private struct PushToStartRegistrationPayload: Encodable {
        let userId: String
        let deviceId: String
        let pushToStartToken: String
        let clientUnixTime: Int
    }

    private struct PushToStartFullCyclePayload: Encodable {
        let userId: String
        let deviceId: String
        let courseName: String
        let courseId: String
        let location: String
        let instructor: String
    }

    private struct PushToStartSchedulePayload: Encodable {
        let schedules: [RemoteCourseActivitySchedule]
    }

    private struct PushToStartSemesterSyncPayload: Encodable {
        let userId: String
        let deviceId: String
        let semester: String
        let semesterEndDate: Int
        let schedules: [RemoteCourseActivitySchedule]
    }

    private struct RemoteCourseActivitySchedule: Encodable {
        let userId: String
        let deviceId: String
        let courseName: String
        let courseId: String
        let location: String
        let instructor: String
        let pushAt: Int
        let classStartDate: Int
        let classEndDate: Int
        let initialPhase: CoursePhase
        let endAt: Int?
        let dismissalDate: Int?
    }

    private struct CancelRemoteSchedulesPayload: Encodable {
        let userId: String
        let deviceId: String
        let semester: String?
        let deactivateToken: Bool
    }

    private struct NotificationIdentity {
        let userId: String
        let deviceId: String
    }

    private struct ServerErrorResponse: Decodable {
        let error: String
    }

    private func observePushToStartTokens() {
        Task {
            for await tokenData in Activity<CourseActivityAttributes>.pushToStartTokenUpdates {
                let tokenHex = hexString(from: tokenData)
                let identity = await notificationIdentity()
                let payload = PushToStartRegistrationPayload(
                    userId: identity.userId,
                    deviceId: identity.deviceId,
                    pushToStartToken: tokenHex,
                    clientUnixTime: unixSeconds(Date())
                )
                if await postJSON(to: "\(serverBaseURL)/push-to-start/register", body: payload) {
                    print("[CourseNotification] ✅ 已向伺服器註冊 push-to-start token")
                    if !lastCourseSnapshot.isEmpty {
                        await scheduleRemoteCourseActivities(
                            for: lastCourseSnapshot,
                            semesterStartDate: nil,
                            semesterEndDate: nil
                        )
                    }
                } else {
                    print("[CourseNotification] ⚠️ push-to-start token 註冊失敗")
                }
            }
        }
    }

    private func observeActivityUpdates() {
        Task {
            for await activity in Activity<CourseActivityAttributes>.activityUpdates {
                let state = activity.content.state
                _ = await registerActivity(
                    activity,
                    courseId: activity.attributes.courseId,
                    startDate: state.classStartDate,
                    endDate: state.classEndDate
                )
                scheduleLocalPhaseUpdates(for: activity, state: state)
            }
        }
    }

    private func scheduleLocalPhaseUpdates(
        for activity: Activity<CourseActivityAttributes>,
        state: CourseActivityAttributes.ContentState
    ) {
        let endTransitionDate = notifyStart ? state.classEndDate : state.classStartDate
        let dismissalDate = notifyEnd && notifyStart
            ? state.classEndDate.addingTimeInterval(liveActivityDismissalDelay)
            : endTransitionDate

        if notifyStart {
            scheduleLocalUpdate(
                for: activity,
                phase: .during,
                startDate: state.classStartDate,
                endDate: state.classEndDate,
                at: state.classStartDate
            )
        }
        scheduleLocalUpdate(
            for: activity,
            phase: .ended,
            startDate: state.classStartDate,
            endDate: state.classEndDate,
            at: endTransitionDate
        )
        scheduleLocalEnd(
            for: activity,
            startDate: state.classStartDate,
            endDate: state.classEndDate,
            at: dismissalDate
        )
    }

    private func scheduleLocalUpdate(
        for activity: Activity<CourseActivityAttributes>,
        phase: CoursePhase,
        startDate: Date,
        endDate: Date,
        at date: Date
    ) {
        let delay = date.timeIntervalSinceNow

        Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let updatedState = CourseActivityAttributes.ContentState(
                phase: phase,
                classStartDate: startDate,
                classEndDate: endDate
            )
            let content = ActivityContent(
                state: updatedState,
                staleDate: endDate.addingTimeInterval(liveActivityDismissalDelay)
            )
            await activity.update(content)
            print("[CourseNotification] ✅ 本機切換遠端啟動 Live Activity: \(activity.id) phase=\(phase.rawValue)")
        }
    }

    private func scheduleLocalEnd(
        for activity: Activity<CourseActivityAttributes>,
        startDate: Date,
        endDate: Date,
        at dismissalDate: Date
    ) {
        let delay = dismissalDate.timeIntervalSinceNow
        guard delay > 0 else { return }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let finalState = CourseActivityAttributes.ContentState(
                phase: .ended,
                classStartDate: startDate,
                classEndDate: endDate
            )
            let content = ActivityContent(state: finalState, staleDate: dismissalDate)
            await activity.end(content, dismissalPolicy: .immediate)
            print("[CourseNotification] ✅ 本機結束遠端啟動 Live Activity: \(activity.id)")
        }
    }

    @discardableResult
    func requestRemoteFullCycleTest(course: Course) async -> Bool {
        let identity = await notificationIdentity()
        let payload = PushToStartFullCyclePayload(
            userId: identity.userId,
            deviceId: identity.deviceId,
            courseName: course.name,
            courseId: course.id,
            location: course.location,
            instructor: course.instructor
        )
        return await postJSON(to: "\(serverBaseURL)/push-to-start/full-cycle", body: payload)
    }

    /// Registers the activity with the server and observes push token updates.
    private func registerActivity(
        _ activity: Activity<CourseActivityAttributes>,
        courseId: String,
        startDate: Date,
        endDate: Date
    ) async -> Bool {
        guard let tokenData = await firstPushToken(for: activity, timeoutSeconds: 15) else {
            print("[CourseNotification] ⚠️ No push token received for activity \(activity.id) within 15 seconds")
            return false
        }

        let tokenHex = hexString(from: tokenData)
        let payload = await registrationPayload(
            activity: activity,
            courseId: courseId,
            tokenHex: tokenHex,
            startDate: startDate,
            endDate: endDate
        )

        guard await postJSON(to: "\(serverBaseURL)/activity/register", body: payload) else {
            print("[CourseNotification] ❌ 向伺服器註冊失敗 activity: \(activity.id)")
            return false
        }
        print("[CourseNotification] ✅ 已向伺服器註冊 activity: \(activity.id)")

        Task {
            await observeTokenRefreshes(
                activity,
                courseId: courseId,
                startDate: startDate,
                endDate: endDate
            )
        }

        return true
    }

    nonisolated private func firstPushToken(
        for activity: Activity<CourseActivityAttributes>,
        timeoutSeconds: UInt64
    ) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                for await tokenData in activity.pushTokenUpdates {
                    return tokenData
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return nil
            }

            let token = await group.next() ?? nil
            group.cancelAll()
            return token
        }
    }

    private func observeTokenRefreshes(
        _ activity: Activity<CourseActivityAttributes>,
        courseId: String,
        startDate: Date,
        endDate: Date
    ) async {
        for await updatedToken in activity.pushTokenUpdates {
            let updatedHex = hexString(from: updatedToken)
            let update = await registrationPayload(
                activity: activity,
                courseId: courseId,
                tokenHex: updatedHex,
                startDate: startDate,
                endDate: endDate
            )

            if await postJSON(to: "\(serverBaseURL)/activity/register", body: update) {
                print("[CourseNotification] 🔄 Push token refreshed for \(activity.id)")
            } else {
                print("[CourseNotification] ⚠️ Push token refresh registration failed for \(activity.id)")
            }
        }
    }

    private func registrationPayload(
        activity: Activity<CourseActivityAttributes>,
        courseId: String,
        tokenHex: String,
        startDate: Date,
        endDate: Date
    ) async -> ActivityRegistrationPayload {
        let identity = await notificationIdentity()
        return ActivityRegistrationPayload(
            userId: identity.userId,
            deviceId: identity.deviceId,
            activityId: activity.id,
            pushToken: tokenHex,
            courseName: activity.attributes.courseName,
            courseId: courseId,
            classStartDate: unixSeconds(startDate),
            classEndDate: unixSeconds(endDate)
        )
    }

    private func notificationIdentity() async -> NotificationIdentity {
        let userId: String
        if let sisSession = try? await SISAuthService.shared.getValidSession() {
            userId = String(sisSession.userId)
        } else if let tronClassSession = try? await TronClassAuthService.shared.getValidSession() {
            userId = String(tronClassSession.userId)
        } else {
            userId = "anonymous"
        }

        return NotificationIdentity(
            userId: userId,
            deviceId: deviceIdentifier()
        )
    }

    @MainActor
    private func deviceIdentifier() -> String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            UserDefaults.standard.set(vendorId, forKey: "courseNotificationDeviceId")
            return vendorId
        }

        if let existing = UserDefaults.standard.string(forKey: "courseNotificationDeviceId") {
            return existing
        }

        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: "courseNotificationDeviceId")
        return generated
    }

    private func cancelRemoteSchedules(semester: String? = nil, deactivateToken: Bool) async {
        let identity = await notificationIdentity()
        let payload = CancelRemoteSchedulesPayload(
            userId: identity.userId,
            deviceId: identity.deviceId,
            semester: semester,
            deactivateToken: deactivateToken
        )
        if await postJSON(to: "\(serverBaseURL)/push-to-start/cancel", body: payload) {
            if let semester {
                print("[CourseNotification] ✅ 已取消伺服器 \(semester) 未來 Live Activity 排程")
            } else {
                print("[CourseNotification] ✅ 已取消伺服器未來 Live Activity 排程")
            }
        } else {
            print("[CourseNotification] ⚠️ 取消伺服器 Live Activity 排程失敗")
        }
    }

    private func unixSeconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Tells the server to stop tracking this activity.
    private func unregisterActivity(id activityId: String) async {
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        guard let encodedActivityId = activityId.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let url = URL(string: "\(serverBaseURL)/activity/\(encodedActivityId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyServerAuth(to: &request)
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[CourseNotification] ⚠️ 登出 activity 收到非 HTTP 回應: \(activityId)")
                return
            }

            if (200..<300).contains(http.statusCode) || http.statusCode == 404 {
                print("[CourseNotification] ✅ 已向伺服器登出 activity: \(activityId)")
            } else {
                let body = String(data: responseData.prefix(300), encoding: .utf8) ?? "(unreadable)"
                print("[CourseNotification] ⚠️ 登出 activity 失敗 HTTP \(http.statusCode): \(body)")
            }
        } catch {
            print("[CourseNotification] ⚠️ 登出 activity 失敗: \(error)")
        }
    }

    /// Fires a JSON POST request and logs server errors.
    private func postJSON<Body: Encodable>(to urlString: String, body: Body) async -> Bool {
        guard let url = URL(string: urlString) else { return false }

        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            print("[CourseNotification] ⚠️ JSON 編碼失敗 (\(urlString)): \(error)")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyServerAuth(to: &request)
        request.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[CourseNotification] ⚠️ POST 收到非 HTTP 回應 (\(urlString))")
                return false
            }

            guard (200..<300).contains(http.statusCode) else {
                let message = serverErrorMessage(from: responseData)
                print("[CourseNotification] ⚠️ 伺服器錯誤 HTTP \(http.statusCode) (\(urlString)): \(message)")
                return false
            }

            return true
        } catch {
            print("[CourseNotification] ⚠️ POST 失敗 (\(urlString)): \(error)")
            return false
        }
    }

    private func serverErrorMessage(from data: Data) -> String {
        if let errorResponse = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
            return errorResponse.error
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "(unreadable)"
    }

    private func applyServerAuth(to request: inout URLRequest) {
        if let serverAuthToken {
            request.setValue("Bearer \(serverAuthToken)", forHTTPHeaderField: "Authorization")
        }
    }
}
