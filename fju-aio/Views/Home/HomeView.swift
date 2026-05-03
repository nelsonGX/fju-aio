import SwiftUI

struct HomeView: View {
    @Environment(\.fjuService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @AppStorage(EventKitSyncService.autoSyncCalendarKey) private var autoSyncCalendar = false

    private let cache = AppCache.shared

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 12)]
    }

    private var todayCourseCardWidth: CGFloat {
        horizontalSizeClass == .regular ? 220 : 170
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection

                if !todayCourses.isEmpty {
                    todayCoursesSection
                }

                moduleGridSection

                if !bulletinNotifications.isEmpty {
                    bulletinSection
                }
            }
            .readableContent()
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("輔大 All In One")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: heroGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 150)

            // Content
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                    Text(dateString)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                // Next course pill
                if let next = nextUpcomingCourse {
                    nextCoursePill(next)
                }
            }
            .padding(20)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 48, y: 24)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 100, height: 100)
                .offset(x: -70, y: -18)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .padding(.top, 8)
    }

    private var heroGradientColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6:   return [Color(hex: "#1a1a2e"), Color(hex: "#16213e")]
        case 6..<10:  return [Color(hex: "#f093fb"), Color(hex: "#f5576c")]
        case 10..<14: return [Color(hex: "#4facfe"), Color(hex: "#00f2fe")]
        case 14..<18: return [Color(hex: "#43e97b"), Color(hex: "#38f9d7")]
        case 18..<21: return [Color(hex: "#fa709a"), Color(hex: "#fee140")]
        default:      return [Color(hex: "#a18cd1"), Color(hex: "#fbc2eb")]
        }
    }

    @ViewBuilder
    private func nextCoursePill(_ course: Course) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("接下來")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(course.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(FJUPeriod.startTime(for: course.startPeriod))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The first upcoming course today (start time hasn't passed yet).
    private var nextUpcomingCourse: Course? {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        return todayCourses.first { course in
            let parts = FJUPeriod.startTime(for: course.startPeriod).split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0]),
                  let m = Int(parts[1]) else { return false }
            return (h * 60 + m) > currentMinutes
        }
    }

    // MARK: - Greeting

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
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
    }

    // MARK: - Today's Courses

    private var todayCoursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "今日課程", icon: "clock.fill", iconColor: .blue)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(todayCourses) { course in
                        todayCourseCard(course)
                            .onTapGesture { selectedCourse = course }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func todayCourseCard(_ course: Course) -> some View {
        let isPast = isCourseInPast(course)
        let isNow = isCourseOngoing(course)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: course.color))
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(isPast ? .secondary : .primary)

                    Text(course.timeSlot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 6) {
                Label(course.location, systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if isNow {
                    Text("上課中")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: course.color), in: Capsule())
                } else {
                    Text(FJUPeriod.startTime(for: course.startPeriod))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isPast ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color(hex: course.color)))
                }
            }
        }
        .padding(12)
        .frame(width: todayCourseCardWidth, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius)
                .stroke(
                    isNow ? Color(hex: course.color).opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .opacity(isPast ? 0.6 : 1)
    }

    private func isCourseInPast(_ course: Course) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute
        let parts = FJUPeriod.startTime(for: course.endPeriod).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (h * 60 + m) < currentMinutes
    }

    private func isCourseOngoing(_ course: Course) -> Bool {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        let startParts = FJUPeriod.startTime(for: course.startPeriod).split(separator: ":")
        let endParts = FJUPeriod.startTime(for: course.endPeriod).split(separator: ":")
        guard startParts.count == 2, endParts.count == 2,
              let sh = Int(startParts[0]), let sm = Int(startParts[1]),
              let eh = Int(endParts[0]), let em = Int(endParts[1]) else { return false }

        let startMinutes = sh * 60 + sm
        let endMinutes = eh * 60 + em + 50 // add period duration
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes
    }

    // MARK: - Module Grid

    private var moduleGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "功能", icon: "square.grid.2x2.fill", iconColor: .orange)
                Spacer()
                Button(action: { isEditing = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.caption)
                        Text("編輯")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }

            if preferences.selectedModules.isEmpty {
                emptyModulesPlaceholder
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(preferences.selectedModules) { module in
                        ModuleCard(module: module)
                    }
                }
            }
        }
    }

    private var emptyModulesPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.accent.opacity(0.6))
            Text("尚未選擇功能")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Button(action: { isEditing = true }) {
                Text("點此新增功能")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Bulletin Notifications

    private var bulletinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "公告通知", icon: "bell.fill", iconColor: .red)

            VStack(spacing: 8) {
                ForEach(bulletinNotifications) { notification in
                    bulletinRow(notification)
                        .onTapGesture { selectedBulletin = notification }
                }
            }
        }
    }

    private func bulletinRow(_ notification: TronClassNotification) -> some View {
        HStack(spacing: 12) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.bulletinTitle ?? "公告")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let courseName = notification.courseName {
                        Text(courseName)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(notification.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let content = notification.bulletinContent.flatMap({ stripHTML($0) }), !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return plain.isEmpty ? nil : plain
    }

    private func loadBulletinNotifications() async {
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
                WidgetDataWriter.shared.writeCourseData(courses: cachedCourses, friends: FriendStore.shared.friends)
                scheduleCourseNotifications(for: cachedCourses, calendarEvents: cachedCalendarEvents)
                await autoSyncCalendarIfNeeded(cachedCalendarEvents)
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
                WidgetDataWriter.shared.writeCourseData(courses: all, friends: FriendStore.shared.friends)

                let todayKey = todayDayString()
                todayCourses = all.filter { $0.dayOfWeek == todayKey }
                    .sorted { $0.startPeriod < $1.startPeriod }
                scheduleCourseNotifications(for: all, calendarEvents: calendarEvents)
                await autoSyncCalendarIfNeeded(calendarEvents)
            }
        } catch {}
        isLoading = false
    }

    private func autoSyncCalendarIfNeeded(_ events: [CalendarEvent]) async {
        guard autoSyncCalendar else { return }
        do {
            try await EventKitSyncService.shared.syncCalendarEvents(events)
        } catch EventKitSyncService.SyncError.calendarAccessDenied {
            EventKitSyncService.shared.disableAutoCalendarSyncForPermissionIssue()
            autoSyncCalendar = false
        } catch {}
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
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        case 1: return "日"
        default: return ""
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline)
        }
    }
}
