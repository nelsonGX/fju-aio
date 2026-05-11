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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection

                todayScheduleSection

                moduleGridSection

                if !bulletinNotifications.isEmpty {
                    bulletinSection
                }
            }
            .readableContent()
            .padding(.bottom, 32)
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
                .frame(height: 160)

            // Decorative circles
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 200, height: 200)
                .offset(x: 120, y: -30)
                .allowsHitTesting(false)
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 110, height: 110)
                .offset(x: 60, y: -80)
                .allowsHitTesting(false)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingText)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text(dateString)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(alignment: .bottomTrailing) {
            if let next = nextUpcomingCourse {
                nextCoursePill(next)
                    .padding(.bottom, 14)
                    .padding(.trailing, 16)
            }
        }
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
        VStack(alignment: .trailing, spacing: 1) {
            Text("接下來")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(course.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
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

    // MARK: - Today's Schedule (vertical list)

    private var todayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "今日課程")
                Spacer()
                NavigationLink(value: AppDestination.courseSchedule) {
                    Text("課表")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                }
            }

            if todayCourses.isEmpty {
                Text(isLoading ? "載入中..." : "今天沒有課，好好休息吧")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayCourses.enumerated()), id: \.element.id) { index, course in
                        Button { selectedCourse = course } label: {
                            todayCourseRow(course, isLast: index == todayCourses.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    private func todayCourseRow(_ course: Course, isLast: Bool) -> some View {
        let isPast = isCourseInPast(course)
        let isNow = isCourseOngoing(course)

        return HStack(spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                Text(FJUPeriod.startTime(for: course.startPeriod))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPast ? AnyShapeStyle(.tertiary) : (isNow ? AnyShapeStyle(Color(hex: course.color)) : AnyShapeStyle(.secondary)))
                Text(FJUPeriod.startTime(for: course.endPeriod))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .frame(width: 44, alignment: .trailing)

            // Color strip
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: course.color).opacity(isPast ? 0.35 : 1))
                .frame(width: 3)
                .padding(.vertical, 4)

            // Course info
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(isPast ? .secondary : .primary)
                Text(course.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Status badge
            if isNow {
                Text("上課中")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: course.color), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(isPast ? 0.65 : 1)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 70)
            }
        }
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

    // MARK: - Module Grid (icon launcher style)

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var moduleGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "功能")
                Spacer()
                Button(action: { isEditing = true }) {
                    Text("編輯")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                }
            }

            if preferences.selectedModules.isEmpty {
                emptyModulesPlaceholder
            } else {
                LazyVGrid(columns: iconColumns, spacing: 16) {
                    ForEach(preferences.selectedModules) { module in
                        ModuleIconCell(module: module)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "公告通知")

            VStack(spacing: 0) {
                ForEach(Array(bulletinNotifications.enumerated()), id: \.element.id) { index, notification in
                    bulletinRow(notification, isLast: index == bulletinNotifications.count - 1)
                        .onTapGesture { selectedBulletin = notification }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private func bulletinRow(_ notification: TronClassNotification, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            // Colored accent strip
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 20)
            }
        }
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

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

// MARK: - Module Icon Cell (launcher style)

private struct ModuleIconCell: View {
    let module: AppModule
    @Environment(\.openURL) private var openURL
    @AppStorage("openLinksInApp") private var openLinksInApp = true
    @State private var showBrowser = false
    @State private var showDormBrowser = false
    private static let dormHost = "dorm.fju.edu.tw"

    var body: some View {
        switch module.type {
        case .inApp(let destination):
            NavigationLink(value: destination) {
                iconCellContent
            }
            .buttonStyle(.plain)
        case .webLink(let url):
            Button {
                handleWebLink(url)
            } label: {
                iconCellContent
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDormBrowser) {
                DormBrowserView().ignoresSafeArea()
            }
            .sheet(isPresented: $showBrowser) {
                InAppBrowserView(url: url).ignoresSafeArea()
            }
        }
    }

    private var iconCellContent: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14)
                .fill(module.color.gradient)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: module.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                }
            Text(module.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func handleWebLink(_ url: URL) {
        if url.host == Self.dormHost {
            showDormBrowser = true
        } else if openLinksInApp && (url.scheme == "https" || url.scheme == "http") {
            showBrowser = true
        } else {
            openURL(url)
        }
    }
}
