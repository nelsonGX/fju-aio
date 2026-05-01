import SwiftUI

struct CourseScheduleView: View {
    @Environment(\.fjuService) private var service
    @Environment(SyncStatusManager.self) private var syncStatus
    @State private var courses: [Course] = []
    @State private var isLoading = true
    @State private var availableSemesters: [String] = []
    @State private var selectedSemester: String = ""
    @State private var selectedCourse: Course?
    @State private var mapHighlightLocation: String? = nil
    @State private var navigateToCampusMap = false
    @State private var showFriendPicker = false
    @State private var visibleFriendIds: Set<String> = []

    private let periodHeight: CGFloat = 56
    private let timeColumnWidth: CGFloat = 38
    private let displayPeriods = 1...11
    private let cache = AppCache.shared

    /// Friends who have a schedule snapshot for the selected semester.
    private var friendsWithSchedule: [FriendRecord] {
        FriendStore.shared.friends.filter {
            $0.cachedProfile?.scheduleSnapshot?.semester == selectedSemester
        }
    }

    /// Color palette assigned to friends (cycles if more than palette count).
    private let friendColorPalette: [Color] = [
        Color(hex: "#FF6B6B"), // red-ish
        Color(hex: "#F7A440"), // orange
        Color(hex: "#4BC98A"), // green
        Color(hex: "#B47CFF"), // purple
        Color(hex: "#FF9EB5"), // pink
        Color(hex: "#5EC4F5"), // sky blue
        Color(hex: "#FFD166"), // yellow
        Color(hex: "#06D6A0"), // teal
    ]

    private func friendColor(for index: Int) -> Color {
        friendColorPalette[index % friendColorPalette.count]
    }

    /// The current weekday (1=Mon … 5=Fri), nil on weekends.
    private var todayWeekdayIndex: Int? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: 1=Sun,2=Mon,...,7=Sat → convert to 0-indexed Mon-Fri
        let index = weekday - 2 // 0=Mon … 4=Fri
        return (0...4).contains(index) ? index : nil
    }

    var body: some View {
        GeometryReader { geometry in
            if isLoading {
                ProgressView("載入中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    timetableGrid(screenWidth: geometry.size.width)
                }
                .refreshable {
                    await loadSemesters(forceRefresh: true)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("課表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Friend schedule overlay button
                    if !friendsWithSchedule.isEmpty {
                        Button {
                            showFriendPicker = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "person.2")
                                    .font(.subheadline)
                                if !visibleFriendIds.isEmpty {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }

                    // Semester picker
                    if !availableSemesters.isEmpty {
                        Menu {
                            ForEach(availableSemesters, id: \.self) { semester in
                                Button {
                                    if semester != selectedSemester {
                                        selectedSemester = semester
                                        visibleFriendIds = []
                                        Task { await loadCourses(forceRefresh: false) }
                                    }
                                } label: {
                                    HStack {
                                        Text(semesterDisplayName(semester))
                                        if semester == selectedSemester {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(semesterDisplayName(selectedSemester))
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course, onOpenMap: {
                mapHighlightLocation = course.location
                selectedCourse = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigateToCampusMap = true
                }
            })
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFriendPicker) {
            FriendSchedulePickerSheet(
                friends: friendsWithSchedule,
                visibleIds: $visibleFriendIds,
                colorForIndex: friendColor
            )
            .presentationDetents([.medium])
        }
        .navigationDestination(isPresented: $navigateToCampusMap) {
            CampusMapView(highlightLocation: mapHighlightLocation)
        }
        .task {
            await loadSemesters(forceRefresh: false)
        }
    }

    // MARK: - Timetable Grid

    private func timetableGrid(screenWidth: CGFloat) -> some View {
        let colWidth = dayColumnWidth(screenWidth: screenWidth)

        return VStack(spacing: 0) {
            headerRow(colWidth: colWidth)
            gridBody(colWidth: colWidth)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private func dayColumnWidth(screenWidth: CGFloat) -> CGFloat {
        (screenWidth - timeColumnWidth - 12) / 5
    }

    // MARK: - Header

    private let weekdays = Array(FJUPeriod.dayNames.prefix(5))

    private func headerRow(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeColumnWidth, height: 32)

            ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(index == todayWeekdayIndex ? .white : .secondary)
                    .frame(width: colWidth, height: 28)
                    .background {
                        if index == todayWeekdayIndex {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 28, height: 28)
                        }
                    }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Grid Body

    private func gridBody(colWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            gridBackground(colWidth: colWidth)
            friendCourseBlocks(colWidth: colWidth)
            courseBlocks(colWidth: colWidth)
        }
        .frame(
            width: timeColumnWidth + CGFloat(5) * colWidth,
            height: CGFloat(displayPeriods.count) * periodHeight
        )
    }

    private func gridBackground(colWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(displayPeriods), id: \.self) { period in
                HStack(spacing: 0) {
                    // Period label
                    VStack(spacing: 1) {
                        Text(FJUPeriod.periodLabel(for: period))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(period == 5 ? Color.orange.opacity(0.8) : .secondary)
                        Text(FJUPeriod.startTime(for: period))
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: timeColumnWidth, height: periodHeight)

                    // Day columns
                    ForEach(0..<5, id: \.self) { dayIndex in
                        Rectangle()
                            .fill(dayIndex == todayWeekdayIndex
                                  ? Color.accentColor.opacity(0.04)
                                  : Color(.systemBackground))
                            .frame(width: colWidth, height: periodHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }

    private func courseBlocks(colWidth: CGFloat) -> some View {
        ForEach(courses.filter { $0.dayOfWeekNumber >= 1 && $0.dayOfWeekNumber <= 5 && displayPeriods.contains($0.startPeriod) }) { course in
            let dayIndex = course.dayOfWeekNumber - 1
            let x = timeColumnWidth + CGFloat(dayIndex) * colWidth + 1.5
            let y = CGFloat(course.startPeriod - displayPeriods.lowerBound) * periodHeight + 1

            CourseCell(course: course, periodHeight: periodHeight)
                .frame(width: colWidth - 3)
                .offset(x: x, y: y)
                .onTapGesture {
                    selectedCourse = course
                }
        }
    }

    // MARK: - Friend Course Blocks

    @ViewBuilder
    private func friendCourseBlocks(colWidth: CGFloat) -> some View {
        let visibleFriends = friendsWithSchedule
            .enumerated()
            .filter { visibleFriendIds.contains($0.element.id) }

        ForEach(Array(visibleFriends), id: \.element.id) { indexedFriend in
            let (friendIndex, friend) = indexedFriend
            let color = friendColor(for: friendIndex)
            let initials = friendInitials(friend.displayName)

            if let snapshot = friend.cachedProfile?.scheduleSnapshot {
                ForEach(snapshot.courses.filter {
                    publicCourseDayNumber($0.dayOfWeek) >= 1 &&
                    publicCourseDayNumber($0.dayOfWeek) <= 5 &&
                    displayPeriods.contains($0.startPeriod)
                }) { publicCourse in
                    let dayIndex = publicCourseDayNumber(publicCourse.dayOfWeek) - 1
                    let x = timeColumnWidth + CGFloat(dayIndex) * colWidth + 1.5
                    let y = CGFloat(publicCourse.startPeriod - displayPeriods.lowerBound) * periodHeight + 1
                    let height = CGFloat(publicCourse.endPeriod - publicCourse.startPeriod + 1) * periodHeight - 2

                    FriendCourseCell(
                        course: publicCourse,
                        friendInitials: initials,
                        color: color,
                        periodHeight: periodHeight
                    )
                    .frame(width: colWidth - 3, height: height)
                    .offset(x: x, y: y)
                }
            }
        }
    }

    private func friendInitials(_ name: String) -> String {
        // Take last character of Chinese name or first letter of English name
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        // If mostly ASCII, use first letter
        let asciiCount = trimmed.filter { $0.isASCII && $0.isLetter }.count
        if asciiCount > trimmed.count / 2 {
            return String(trimmed.prefix(1)).uppercased()
        }
        // Chinese name: last character
        return String(trimmed.suffix(1))
    }

    private func publicCourseDayNumber(_ dayOfWeek: String) -> Int {
        switch dayOfWeek {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "日": return 7
        default: return 0
        }
    }

    // MARK: - Data Loading

    private func loadSemesters(forceRefresh: Bool) async {
        // Use cached semesters if available
        if !forceRefresh, let cached = cache.getSemesters() {
            availableSemesters = cached
            if selectedSemester.isEmpty, let first = cached.first {
                selectedSemester = first
            }
            await loadCourses(forceRefresh: false)
            return
        }

        do {
            let semesters = try await service.fetchAvailableSemesters()
            availableSemesters = semesters
            cache.setSemesters(semesters)
            if selectedSemester.isEmpty, let first = semesters.first {
                selectedSemester = first
            }
            await loadCourses(forceRefresh: forceRefresh)
        } catch {
            if selectedSemester.isEmpty {
                selectedSemester = "114-2"
            }
            await loadCourses(forceRefresh: forceRefresh)
        }
    }

    private func loadCourses(forceRefresh: Bool) async {
        guard !selectedSemester.isEmpty else { return }

        // Serve from cache without showing spinner
        if !forceRefresh, let cached = cache.getCourses(semester: selectedSemester) {
            courses = cached
            isLoading = false
            scheduleCourseNotifications(for: cached)
            return
        }

        isLoading = true
        do {
            try await syncStatus.withSync("正在載入課表…") {
                let fetched = try await service.fetchCourses(semester: selectedSemester)
                courses = fetched
                cache.setCourses(fetched, semester: selectedSemester)
            }
        } catch {
            courses = []
        }
        isLoading = false

        // Schedule notifications and Live Activity in the background after UI is shown
        scheduleCourseNotifications(for: courses)
    }

    private func scheduleCourseNotifications(for courses: [Course]) {
        let snapshot = courses
        Task(priority: .background) {
            await CourseNotificationManager.shared.scheduleAll(for: snapshot)
        }
    }

    private func semesterDisplayName(_ semester: String) -> String {
        let parts = semester.split(separator: "-")
        guard parts.count == 2 else { return semester }
        return "\(parts[0])學年 第\(parts[1])學期"
    }
}

// MARK: - Friend Course Cell

private struct FriendCourseCell: View {
    let course: PublicCourseInfo
    let friendInitials: String
    let color: Color
    let periodHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    // Friend initial badge
                    Text(friendInitials)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(color))

                    Text(course.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }

                if course.location.isEmpty == false,
                   CGFloat(course.endPeriod - course.startPeriod + 1) * periodHeight - 2 > periodHeight * 0.9 {
                    Text(course.location)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(color.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Friend Schedule Picker Sheet

private struct FriendSchedulePickerSheet: View {
    let friends: [FriendRecord]
    @Binding var visibleIds: Set<String>
    let colorForIndex: (Int) -> Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                        HStack(spacing: 12) {
                            // Color swatch
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorForIndex(index))
                                .frame(width: 20, height: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                    .font(.body)
                                if let snap = friend.cachedProfile?.scheduleSnapshot {
                                    Text("\(snap.courses.count) 門課")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if visibleIds.contains(friend.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(colorForIndex(index))
                                    .font(.title3)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if visibleIds.contains(friend.id) {
                                visibleIds.remove(friend.id)
                            } else {
                                visibleIds.insert(friend.id)
                            }
                        }
                    }
                } header: {
                    Text("選擇要顯示的朋友課表")
                } footer: {
                    Text("只顯示本學期有課表快照的朋友")
                }
            }
            .navigationTitle("朋友課表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(visibleIds.count == friends.count ? "全部取消" : "全選") {
                        if visibleIds.count == friends.count {
                            visibleIds = []
                        } else {
                            visibleIds = Set(friends.map(\.id))
                        }
                    }
                }
            }
        }
    }
}
