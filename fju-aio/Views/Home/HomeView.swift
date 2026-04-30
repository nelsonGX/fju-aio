import SwiftUI

struct HomeView: View {
    @Environment(\.fjuService) private var service
    @Environment(HomePreferences.self) private var preferences
    @Environment(SyncStatusManager.self) private var syncStatus
    @State private var todayCourses: [Course] = []
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var selectedCourse: Course?
    @State private var lastNotificationSyncSignature: String?
    @State private var mapHighlightLocation: String? = nil
    @State private var navigateToCampusMap = false
    @State private var bulletinNotifications: [TronClassNotification] = []
    @State private var selectedBulletin: TronClassNotification?

    private let cache = AppCache.shared

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                greetingSection

                if !todayCourses.isEmpty {
                    todayCoursesSection
                }

                moduleGridSection

                if !bulletinNotifications.isEmpty {
                    bulletinSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("FJU AIO")
        .refreshable {
            await loadTodayCourses(forceRefresh: true)
            await loadBulletinNotifications()
        }
        .sheet(isPresented: $isEditing) {
            HomeEditView()
        }
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course, onOpenMap: {
                mapHighlightLocation = course.location
                selectedCourse = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigateToCampusMap = true
                }
            })
            .presentationDetents([.medium])
        }
        .navigationDestination(isPresented: $navigateToCampusMap) {
            CampusMapView(highlightLocation: mapHighlightLocation)
        }
        .sheet(item: $selectedBulletin) { bulletin in
            BulletinDetailView(notification: bulletin)
        }
        .task {
            await loadTodayCourses(forceRefresh: false)
            await loadBulletinNotifications()
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.title2.weight(.bold))
            Text(dateString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "夜深了"
        case 6..<12: return "早安"
        case 12..<18: return "午安"
        default: return "晚安"
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: Date())
    }

    // MARK: - Today's Courses

    private var todayCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日課程")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(todayCourses) { course in
                        todayCourseCard(course)
                            .onTapGesture { selectedCourse = course }
                    }
                }
            }
        }
    }

    private func todayCourseCard(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(course.location)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Text(course.timeSlot)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            Text(FJUPeriod.startTime(for: course.startPeriod))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(12)
        .frame(width: 140, alignment: .leading)
        .background(Color(hex: course.color), in: RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius))
    }

    // MARK: - Module Grid

    private var moduleGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("功能")
                    .font(.headline)
                Spacer()
                Button(action: { isEditing = true }) {
                    Text("編輯")
                        .font(.subheadline)
                }
            }

            if preferences.selectedModules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("尚未選擇功能")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("點擊「編輯」加入常用功能")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(preferences.selectedModules) { module in
                        ModuleCard(module: module)
                    }
                }
            }
        }
    }

    // MARK: - Bulletin Notifications

    private var bulletinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("公告通知")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(bulletinNotifications) { notification in
                    bulletinRow(notification)
                        .onTapGesture { selectedBulletin = notification }
                }
            }
        }
    }

    private func bulletinRow(_ notification: TronClassNotification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notification.bulletinTitle ?? "公告")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let courseName = notification.courseName {
                Text(courseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let content = notification.bulletinContent.flatMap({ stripHTML($0) }), !content.isEmpty {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(notification.date, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius))
    }

    /// Strip HTML tags and decode common entities for display.
    private func stripHTML(_ html: String) -> String? {
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            // Collapse runs of whitespace / newlines into a single space
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return plain.isEmpty ? nil : plain
    }

    private func loadBulletinNotifications() async {
        // Escalate the fetch limit until we collect at least 5 bulletin_created entries.
        let limits = [50, 100, 200]
        do {
            for limit in limits {
                let results = try await TronClassAPIService.shared.getNotifications(limit: limit)
                bulletinNotifications = results
                if results.count >= 5 { break }
            }
        } catch {
            // Silently fail — notifications are non-critical
        }
    }

    // MARK: - Data Loading

    private func loadTodayCourses(forceRefresh: Bool) async {
        // Serve cached courses for today without showing a spinner
        if !forceRefresh {
            let todayKey = todayDayString()
            if let cachedSemesters = cache.getSemesters(),
               let currentSemester = cachedSemesters.first,
               let cachedCourses = cache.getCourses(semester: currentSemester) {
                let cachedCalendarEvents = cache.getCalendarEvents(semester: currentSemester) ?? []
                todayCourses = cachedCourses
                    .filter { $0.dayOfWeek == todayKey }
                    .sorted { $0.startPeriod < $1.startPeriod }
                isLoading = false
                scheduleCourseNotifications(for: cachedCourses, calendarEvents: cachedCalendarEvents)
                return
            }
        }

        isLoading = true
        do {
            try await syncStatus.withSync("正在載入課程…") {
                let semesters = try await service.fetchAvailableSemesters()
                let currentSemester = semesters.first ?? "114-2"
                let all = try await service.fetchCourses(semester: currentSemester)
                let calendarEvents = (try? await service.fetchCalendarEvents(semester: currentSemester)) ?? []

                cache.setSemesters(semesters)
                cache.setCourses(all, semester: currentSemester)
                cache.setCalendarEvents(calendarEvents, semester: currentSemester)

                let todayKey = todayDayString()
                todayCourses = all.filter { $0.dayOfWeek == todayKey }
                    .sorted { $0.startPeriod < $1.startPeriod }
                scheduleCourseNotifications(for: all, calendarEvents: calendarEvents)
            }
        } catch {}
        isLoading = false
    }

    private func scheduleCourseNotifications(for courses: [Course], calendarEvents: [CalendarEvent]) {
        let snapshot = courses
        let semester = courses.first { !$0.semester.isEmpty }?.semester ?? ""
        let window = SemesterCalendarResolver.notificationWindow(
            for: semester,
            events: calendarEvents
        )
        let signature = notificationSyncSignature(
            courses: snapshot,
            semester: semester,
            window: window
        )
        guard signature != lastNotificationSyncSignature else { return }
        lastNotificationSyncSignature = signature

        print("[CourseNotification] calendar window semester=\(window.semester), start=\(String(describing: window.startDate)), end=\(String(describing: window.endDate)), source=\(window.source)")
        Task(priority: .background) {
            await CourseNotificationManager.shared.scheduleAll(
                for: snapshot,
                semesterStartDate: window.startDate,
                semesterEndDate: window.endDate
            )
        }
    }

    private func notificationSyncSignature(
        courses: [Course],
        semester: String,
        window: SemesterNotificationWindow
    ) -> String {
        let courseSignature = courses
            .sorted { $0.id < $1.id }
            .map {
                [
                    $0.id,
                    $0.dayOfWeek,
                    String($0.startPeriod),
                    String($0.endPeriod),
                    $0.location,
                    $0.weeks
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        return [
            semester,
            String(window.startDate?.timeIntervalSince1970 ?? 0),
            String(window.endDate?.timeIntervalSince1970 ?? 0),
            courseSignature
        ].joined(separator: "#")
    }

    private func todayDayString() -> String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        switch weekday {
        case 2: return "一" // Monday
        case 3: return "二" // Tuesday
        case 4: return "三" // Wednesday
        case 5: return "四" // Thursday
        case 6: return "五" // Friday
        case 7: return "六" // Saturday
        case 1: return "日" // Sunday
        default: return ""
        }
    }
}
