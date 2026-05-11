import SwiftUI
import os.log

struct CourseScheduleView: View {
    @Environment(\.fjuService) private var service
    @Environment(SyncStatusManager.self) private var syncStatus
    @State private var courses: [Course] = []
    @State private var pendingDeepLinkedCourseID: String?
    @State private var isLoading = true
    @State private var availableSemesters: [String] = []
    @State private var selectedSemester: String = ""
    @State private var selectedCourseDetail: CourseDetailSelection?
    @State private var selectedFriendSlotDetail: FriendSlotDetail?
    @State private var mapHighlightLocation: String? = nil
    @State private var navigateToCampusMap = false
    @State private var showFriendPicker = false
    @State private var showShareSheet = false
    @State private var visibleFriendIds: Set<String> = []
    @AppStorage("courseSchedule.showSelfCourses") private var showSelfCourses = true

    private let periodHeight: CGFloat = 56
    private let timeColumnWidth: CGFloat = 38
    private let displayPeriods = 1...11
    private let visibleFriendIdsStoragePrefix = "courseSchedule.visibleFriendIds."
    private let cache = AppCache.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "CourseSchedule")

    init(deepLinkedCourseID: String? = nil) {
        _pendingDeepLinkedCourseID = State(initialValue: deepLinkedCourseID)
    }

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
                    timetableGrid(screenWidth: min(geometry.size.width, AppTheme.readableContentMaxWidth))
                        .frame(maxWidth: .infinity, alignment: .center)
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
                HStack(spacing: 6) {
                    // Share button
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                            .padding(4)
                            .offset(y: -2)
                    }
                    .disabled(courses.isEmpty)

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
                                        restoreVisibleFriendIds()
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
                                Text(selectedSemester)
                                    .font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedCourseDetail) { selection in
            CourseDetailSheet(
                course: selection.course,
                overlappingFriendCourses: selection.overlappingFriendCourses,
                onOpenMap: {
                mapHighlightLocation = selection.course.location
                selectedCourseDetail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigateToCampusMap = true
                }
            })
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedFriendSlotDetail) { detail in
            FriendSlotDetailSheet(detail: detail)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showFriendPicker) {
            FriendSchedulePickerSheet(
                friends: friendsWithSchedule,
                visibleIds: $visibleFriendIds,
                showSelfCourses: $showSelfCourses,
                colorForIndex: friendColor
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showShareSheet) {
            CourseShareSheet(courses: courses, semester: selectedSemester)
                .presentationDetents([.medium])
        }
        .navigationDestination(isPresented: $navigateToCampusMap) {
            CampusMapView(highlightLocation: mapHighlightLocation)
        }
        .task {
            await loadSemesters(forceRefresh: false)
        }
        .onChange(of: visibleFriendIds) { _, _ in
            saveVisibleFriendIds()
        }
        .onChange(of: courses) { _, _ in
            presentDeepLinkedCourseIfNeeded()
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
            if showSelfCourses {
                courseBlocks(colWidth: colWidth)
            }
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
                                  ? Color.accentColor.opacity(0.07)
                                  : Color(.systemBackground))
                            .frame(width: colWidth, height: periodHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func courseBlocks(colWidth: CGFloat) -> some View {
        let layouts = activeScheduleLayouts

        ForEach(courses.filter { $0.dayOfWeekNumber >= 1 && $0.dayOfWeekNumber <= 5 && displayPeriods.contains($0.startPeriod) }) { course in
            let dayIndex = course.dayOfWeekNumber - 1
            let blockLayout = ScheduleBlockLayout(
                id: "self-\(course.id)",
                isSelf: true,
                dayIndex: dayIndex,
                startPeriod: course.startPeriod,
                endPeriod: course.endPeriod,
                order: selfCourseLayoutOrder,
                labelHeight: estimatedSelfLabelHeight(for: course)
            )
            let overlap = overlapLayout(for: blockLayout, in: layouts)
            let metrics = overlapMetrics(for: blockLayout, overlap: overlap, colWidth: colWidth)
            let x = timeColumnWidth + CGFloat(dayIndex) * colWidth + 1.5 + metrics.xOffset
            let y = CGFloat(course.startPeriod - displayPeriods.lowerBound) * periodHeight + 1

            CourseCell(
                course: course,
                periodHeight: periodHeight,
                contentAlignment: metrics.alignment,
                contentYOffset: metrics.textYOffset,
                backgroundOpacity: metrics.backgroundOpacity,
                contentOpacity: metrics.contentOpacity,
                contentFrameAlignment: metrics.contentFrameAlignment,
                ownerBadgeText: visibleFriendIds.isEmpty ? nil : selfCourseBadgeText,
                ownerBadgeColor: .white
            )
                .frame(width: colWidth - 3)
                .offset(x: x, y: y)
                .zIndex(metrics.zIndex + 20)
                .onTapGesture {
                    selectedCourseDetail = CourseDetailSelection(
                        course: course,
                        overlappingFriendCourses: friendOccurrences(overlapping: course)
                    )
                }
        }
    }

    // MARK: - Friend Course Blocks

    @ViewBuilder
    private func friendCourseBlocks(colWidth: CGFloat) -> some View {
        let layouts = activeScheduleLayouts
        let visibleFriends = friendsWithSchedule
            .enumerated()
            .filter { visibleFriendIds.contains($0.element.id) }

        ForEach(Array(visibleFriends), id: \.element.id) { indexedFriend in
            let (friendIndex, friend) = indexedFriend
            let color = friendColor(for: friendIndex)
            let badgeText = ownerBadgeText(friend.displayName, fallback: "?")

            if let snapshot = friend.cachedProfile?.scheduleSnapshot {
                ForEach(snapshot.courses.filter {
                    publicCourseDayNumber($0.dayOfWeek) >= 1 &&
                    publicCourseDayNumber($0.dayOfWeek) <= 5 &&
                    displayPeriods.contains($0.startPeriod)
                }) { publicCourse in
                    let dayIndex = publicCourseDayNumber(publicCourse.dayOfWeek) - 1
                    let blockLayout = ScheduleBlockLayout(
                        id: "friend-\(friend.id)-\(publicCourse.id)",
                        isSelf: false,
                        dayIndex: dayIndex,
                        startPeriod: publicCourse.startPeriod,
                        endPeriod: publicCourse.endPeriod,
                        order: friendIndex + 1,
                        labelHeight: estimatedFriendLabelHeight(for: publicCourse)
                    )
                    let overlap = overlapLayout(for: blockLayout, in: layouts)
                    let metrics = overlapMetrics(for: blockLayout, overlap: overlap, colWidth: colWidth)
                    let x = timeColumnWidth + CGFloat(dayIndex) * colWidth + 1.5 + metrics.xOffset
                    let y = CGFloat(publicCourse.startPeriod - displayPeriods.lowerBound) * periodHeight + 1
                    let height = CGFloat(publicCourse.endPeriod - publicCourse.startPeriod + 1) * periodHeight - 2

                    FriendCourseCell(
                        course: publicCourse,
                        friendInitials: badgeText,
                        color: color,
                        periodHeight: periodHeight,
                        contentAlignment: metrics.alignment,
                        contentYOffset: metrics.textYOffset,
                        backgroundOpacity: metrics.backgroundOpacity,
                        contentOpacity: metrics.contentOpacity
                    )
                    .frame(width: colWidth - 3, height: height)
                    .offset(x: x, y: y)
                    .zIndex(metrics.zIndex)
                    .onTapGesture {
                        let occurrence = FriendCourseOccurrence(
                            friendId: friend.id,
                            friendName: friend.displayName,
                            badgeText: badgeText,
                            color: color,
                            course: publicCourse
                        )

                        if let selfCourse = selfCourse(overlapping: publicCourse) {
                            selectedCourseDetail = CourseDetailSelection(
                                course: selfCourse,
                                overlappingFriendCourses: friendOccurrences(overlapping: selfCourse)
                            )
                        } else {
                            selectedFriendSlotDetail = FriendSlotDetail(
                                title: "這個時段中...",
                                subtitle: "星期\(publicCourse.dayOfWeek) 第\(FJUPeriod.periodLabel(for: publicCourse.startPeriod))-\(FJUPeriod.periodLabel(for: publicCourse.endPeriod))節",
                                courses: friendOccurrences(overlapping: occurrence)
                            )
                        }
                    }
                }
            }
        }
    }

    private var activeScheduleLayouts: [ScheduleBlockLayout] {
        var layouts: [ScheduleBlockLayout] = []

        if showSelfCourses {
            layouts += courses
                .filter {
                    $0.dayOfWeekNumber >= 1 &&
                    $0.dayOfWeekNumber <= 5 &&
                    displayPeriods.contains($0.startPeriod)
                }
                .map {
                    ScheduleBlockLayout(
                        id: "self-\($0.id)",
                        isSelf: true,
                        dayIndex: $0.dayOfWeekNumber - 1,
                        startPeriod: $0.startPeriod,
                        endPeriod: $0.endPeriod,
                        order: selfCourseLayoutOrder,
                        labelHeight: estimatedSelfLabelHeight(for: $0)
                    )
                }
        }

        for (friendIndex, friend) in friendsWithSchedule.enumerated() where visibleFriendIds.contains(friend.id) {
            guard let snapshot = friend.cachedProfile?.scheduleSnapshot else { continue }
            layouts += snapshot.courses
                .filter {
                    publicCourseDayNumber($0.dayOfWeek) >= 1 &&
                    publicCourseDayNumber($0.dayOfWeek) <= 5 &&
                    displayPeriods.contains($0.startPeriod)
                }
                .map {
                    ScheduleBlockLayout(
                        id: "friend-\(friend.id)-\($0.id)",
                        isSelf: false,
                        dayIndex: publicCourseDayNumber($0.dayOfWeek) - 1,
                        startPeriod: $0.startPeriod,
                        endPeriod: $0.endPeriod,
                        order: friendIndex + 1,
                        labelHeight: estimatedFriendLabelHeight(for: $0)
                    )
                }
        }

        return layouts
    }

    private func overlapLayout(
        for block: ScheduleBlockLayout,
        in layouts: [ScheduleBlockLayout]
    ) -> (index: Int, count: Int, laneYOffset: CGFloat) {
        let overlapping = layouts
            .filter { $0.dayIndex == block.dayIndex && $0.overlaps(block) }
            .sorted {
                if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
                if $0.endPeriod != $1.endPeriod { return $0.endPeriod < $1.endPeriod }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.id < $1.id
            }

        guard overlapping.count > 1,
              let index = overlapping.firstIndex(where: { $0.id == block.id }) else {
            return (0, 1, 0)
        }

        let groupStartPeriod = overlapping.map(\.startPeriod).min() ?? block.startPeriod
        let absoluteLaneYOffset = overlapping[..<index].reduce(CGFloat(0)) { $0 + $1.labelHeight + 8 }
        let blockYOffsetFromGroup = CGFloat(block.startPeriod - groupStartPeriod) * periodHeight
        let relativeLaneYOffset = max(0, absoluteLaneYOffset - blockYOffsetFromGroup)
        return (index, overlapping.count, relativeLaneYOffset)
    }

    private func overlapMetrics(
        for block: ScheduleBlockLayout,
        overlap: (index: Int, count: Int, laneYOffset: CGFloat),
        colWidth: CGFloat
    ) -> OverlapMetrics {
        let fullWidth = colWidth - 3
        guard overlap.count > 1 else {
            return OverlapMetrics(
                width: fullWidth,
                xOffset: 0,
                textYOffset: 0,
                backgroundOpacity: 1,
                contentOpacity: 1,
                contentFrameAlignment: .center,
                alignment: .leading,
                zIndex: 0
            )
        }

        let blockHeight = CGFloat(block.endPeriod - block.startPeriod + 1) * periodHeight - 2
        let maxTextYOffset = max(0, blockHeight - block.labelHeight - 4)
        let textYOffset = block.isSelf ? 0 : min(overlap.laneYOffset, maxTextYOffset)

        return OverlapMetrics(
            width: fullWidth,
            xOffset: 0,
            textYOffset: textYOffset,
            backgroundOpacity: block.isSelf ? 0.55 : 0.32,
            contentOpacity: block.isSelf ? 1 : 0.86,
            contentFrameAlignment: block.isSelf ? .topLeading : .center,
            alignment: .leading,
            zIndex: block.isSelf ? 100 : Double(overlap.index)
        )
    }

    private var selfCourseLayoutOrder: Int {
        0
    }

    private func estimatedSelfLabelHeight(for course: Course) -> CGFloat {
        let duration = course.endPeriod - course.startPeriod + 1
        let nameLineCount: CGFloat = course.name.count > 7 && duration > 1 ? 1.5 : 0.8
        let locationHeight: CGFloat = duration > 1 ? 13 : 0
        return 10 + nameLineCount * 10 + locationHeight
    }

    private func estimatedFriendLabelHeight(for course: PublicCourseInfo) -> CGFloat {
        let duration = course.endPeriod - course.startPeriod + 1
        let locationHeight: CGFloat = duration > 1 && !course.location.isEmpty ? 11 : 0
        return 10 + locationHeight
    }

    private var selfCourseBadgeText: String {
        ownerBadgeText("我", fallback: "我")
    }

    private func ownerBadgeText(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return fallback }

        if trimmed.allSatisfy({ $0.isASCII }) {
            let parts = trimmed.split(separator: " ")
            let lastName = parts.last.map(String.init) ?? trimmed
            return String(lastName.prefix(1)).uppercased()
        }

        return String(trimmed.prefix(1))
    }

    private func selfCourse(overlapping publicCourse: PublicCourseInfo) -> Course? {
        guard showSelfCourses else { return nil }

        return courses.first {
            $0.dayOfWeekNumber == publicCourseDayNumber(publicCourse.dayOfWeek) &&
            $0.startPeriod <= publicCourse.endPeriod &&
            $0.endPeriod >= publicCourse.startPeriod
        }
    }

    private func friendOccurrences(overlapping selfCourse: Course) -> [FriendCourseOccurrence] {
        friendOccurrences().filter {
            publicCourseDayNumber($0.course.dayOfWeek) == selfCourse.dayOfWeekNumber &&
            $0.course.startPeriod <= selfCourse.endPeriod &&
            $0.course.endPeriod >= selfCourse.startPeriod
        }
    }

    private func friendOccurrences(overlapping occurrence: FriendCourseOccurrence) -> [FriendCourseOccurrence] {
        friendOccurrences().filter {
            publicCourseDayNumber($0.course.dayOfWeek) == publicCourseDayNumber(occurrence.course.dayOfWeek) &&
            $0.course.startPeriod <= occurrence.course.endPeriod &&
            $0.course.endPeriod >= occurrence.course.startPeriod
        }
    }

    private func friendOccurrences() -> [FriendCourseOccurrence] {
        friendsWithSchedule.enumerated().flatMap { friendIndex, friend -> [FriendCourseOccurrence] in
            guard visibleFriendIds.contains(friend.id),
                  let snapshot = friend.cachedProfile?.scheduleSnapshot else { return [] }

            let color = friendColor(for: friendIndex)
            let badgeText = ownerBadgeText(friend.displayName, fallback: "?")
            return snapshot.courses
                .filter {
                    publicCourseDayNumber($0.dayOfWeek) >= 1 &&
                    publicCourseDayNumber($0.dayOfWeek) <= 5 &&
                    displayPeriods.contains($0.startPeriod)
                }
                .map {
                    FriendCourseOccurrence(
                        friendId: friend.id,
                        friendName: friend.displayName,
                        badgeText: badgeText,
                        color: color,
                        course: $0
                    )
                }
        }
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
            logger.info("📅 loadSemesters using cache forceRefresh=\(forceRefresh, privacy: .public), cached=\(cached.description, privacy: .public)")
            if cached.count > 6 {
                logger.warning("⚠️ Cached semesters contains unusually many entries: \(cached.description, privacy: .public)")
            } else {
                availableSemesters = cached
                if selectedSemester.isEmpty, let first = cached.first {
                    selectedSemester = first
                }
                restoreVisibleFriendIds()
                await loadCourses(forceRefresh: false)
                return
            }
        }

        do {
            let semesters = try await service.fetchAvailableSemesters()
            logger.info("📅 loadSemesters fetched forceRefresh=\(forceRefresh, privacy: .public), semesters=\(semesters.description, privacy: .public)")
            if semesters.count > 6 {
                logger.warning("⚠️ Fetched semesters contains unusually many entries: \(semesters.description, privacy: .public)")
            }
            availableSemesters = semesters
            cache.setSemesters(semesters)
            if selectedSemester.isEmpty, let first = semesters.first {
                selectedSemester = first
            }
            restoreVisibleFriendIds()
            await loadCourses(forceRefresh: forceRefresh)
        } catch {
            if selectedSemester.isEmpty, let cached = cache.getSemesters()?.first {
                selectedSemester = cached
            } else if selectedSemester.isEmpty {
                selectedSemester = "114-2"
            }
            restoreVisibleFriendIds()
            await loadCourses(forceRefresh: false)
        }
    }

    private func loadCourses(forceRefresh: Bool) async {
        guard !selectedSemester.isEmpty else { return }

        // Serve from cache without showing spinner
        if !forceRefresh, let cached = cache.getCourses(semester: selectedSemester) {
            courses = cached
            isLoading = false
            presentDeepLinkedCourseIfNeeded()
            WidgetDataWriter.shared.writeCourseData(courses: cached, friends: FriendStore.shared.friends)
            scheduleCourseNotifications(for: cached)
            return
        }

        isLoading = true
        do {
            try await syncStatus.withSync("正在載入課表…") {
                let fetched = try await service.fetchCourses(semester: selectedSemester)
                courses = fetched
                cache.setCourses(fetched, semester: selectedSemester)
                WidgetDataWriter.shared.writeCourseData(courses: fetched, friends: FriendStore.shared.friends)
            }
        } catch {
            if courses.isEmpty, let cached = cache.getCourses(semester: selectedSemester) {
                courses = cached
                WidgetDataWriter.shared.writeCourseData(courses: cached, friends: FriendStore.shared.friends)
            }
        }
        isLoading = false
        presentDeepLinkedCourseIfNeeded()

        // Schedule notifications and Live Activity in the background after UI is shown
        scheduleCourseNotifications(for: courses)
    }

    private func presentDeepLinkedCourseIfNeeded() {
        guard let courseID = pendingDeepLinkedCourseID,
              selectedCourseDetail == nil,
              let course = courses.first(where: { $0.id == courseID || $0.code == courseID })
        else { return }

        pendingDeepLinkedCourseID = nil
        selectedCourseDetail = CourseDetailSelection(
            course: course,
            overlappingFriendCourses: friendOccurrences(overlapping: course)
        )
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

    private func restoreVisibleFriendIds() {
        guard !selectedSemester.isEmpty else { return }

        let availableIds = Set(friendsWithSchedule.map(\.id))
        let savedIds = loadVisibleFriendIds(for: selectedSemester)
        visibleFriendIds = savedIds.intersection(availableIds)
    }

    private func saveVisibleFriendIds() {
        guard !selectedSemester.isEmpty else { return }

        let ids = Array(visibleFriendIds).sorted()
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: visibleFriendIdsStorageKey(for: selectedSemester))
        }
    }

    private func loadVisibleFriendIds(for semester: String) -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: visibleFriendIdsStorageKey(for: semester)),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return Set(ids)
    }

    private func visibleFriendIdsStorageKey(for semester: String) -> String {
        visibleFriendIdsStoragePrefix + semester
    }
}

// MARK: - Friend Course Cell

private struct FriendCourseCell: View {
    let course: PublicCourseInfo
    let friendInitials: String
    let color: Color
    let periodHeight: CGFloat
    let contentAlignment: HorizontalAlignment
    let contentYOffset: CGFloat
    let backgroundOpacity: Double
    let contentOpacity: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.mixed(with: .white, by: 0.25).opacity(0.32 * backgroundOpacity),
                            color.opacity(0.22 * backgroundOpacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color.opacity(0.85 * backgroundOpacity), lineWidth: 1.5)
                )

            VStack(alignment: contentAlignment, spacing: 2) {
                HStack(spacing: 3) {
                    // Friend initial badge
                    Text(friendInitials)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(contentOpacity))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(color.mixed(with: .black, by: 0.1).opacity(contentOpacity)))

                    Text(course.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color.mixed(with: .black, by: 0.2).opacity(contentOpacity))
                        .lineLimit(1)
                }

                if course.location.isEmpty == false,
                   CGFloat(course.endPeriod - course.startPeriod + 1) * periodHeight - 2 > periodHeight * 0.9 {
                    Text(course.location)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(color.mixed(with: .black, by: 0.25).opacity(0.9 * contentOpacity))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: contentAlignment == .trailing ? .trailing : .leading)
            .offset(y: contentYOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CourseDetailSelection: Identifiable {
    let course: Course
    let overlappingFriendCourses: [FriendCourseOccurrence]

    var id: String {
        [course.id, overlappingFriendCourses.map(\.id).joined(separator: ",")].joined(separator: "|")
    }
}

struct FriendCourseOccurrence: Identifiable {
    let friendId: String
    let friendName: String
    let badgeText: String
    let color: Color
    let course: PublicCourseInfo

    var id: String {
        "\(friendId)-\(course.id)"
    }
}

private struct FriendSlotDetail: Identifiable {
    let title: String
    let subtitle: String
    let courses: [FriendCourseOccurrence]

    var id: String {
        [title, subtitle, courses.map(\.id).joined(separator: ",")].joined(separator: "|")
    }
}

private struct FriendSlotDetailSheet: View {
    let detail: FriendSlotDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(detail.courses) { occurrence in
                        FriendCourseOccurrenceRow(occurrence: occurrence)
                    }
                } header: {
                    Text(detail.subtitle)
                }
            }
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct FriendCourseOccurrenceRow: View {
    let occurrence: FriendCourseOccurrence

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(occurrence.badgeText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(occurrence.color))

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(occurrence.friendName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(friendCourseTimeAndLocation(occurrence.course))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func friendCourseTimeAndLocation(_ course: PublicCourseInfo) -> String {
        let start = FJUPeriod.periodLabel(for: course.startPeriod)
        let end = FJUPeriod.periodLabel(for: course.endPeriod)
        let time = start == end ? "星期\(course.dayOfWeek) 第\(start)節" : "星期\(course.dayOfWeek) 第\(start)-\(end)節"
        return course.location.isEmpty ? time : "\(time) · \(course.location)"
    }
}

private struct ScheduleBlockLayout: Identifiable, Hashable {
    let id: String
    let isSelf: Bool
    let dayIndex: Int
    let startPeriod: Int
    let endPeriod: Int
    let order: Int
    let labelHeight: CGFloat

    func overlaps(_ other: ScheduleBlockLayout) -> Bool {
        startPeriod <= other.endPeriod && endPeriod >= other.startPeriod
    }
}

private struct OverlapMetrics {
    let width: CGFloat
    let xOffset: CGFloat
    let textYOffset: CGFloat
    let backgroundOpacity: Double
    let contentOpacity: Double
    let contentFrameAlignment: Alignment
    let alignment: HorizontalAlignment
    let zIndex: Double
}

// MARK: - Friend Schedule Picker Sheet

private struct FriendSchedulePickerSheet: View {
    let friends: [FriendRecord]
    @Binding var visibleIds: Set<String>
    @Binding var showSelfCourses: Bool
    let colorForIndex: (Int) -> Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $showSelfCourses) {
                        Label("顯示自己的課表", systemImage: "person.crop.rectangle")
                    }
                }

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
// MARK: - Course Share Sheet

private struct CourseShareSheet: View {
    let courses: [Course]
    let semester: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myProfile.scheduleVisibility") private var scheduleVisibilityRaw = ScheduleVisibility.friendsOnly.rawValue
    @AppStorage("myProfile.isPublished") private var isPublished = false
    @State private var showingNTUTExport = false
    @State private var ntutJSON: String = ""

    private var scheduleAlreadyShared: Bool {
        guard isPublished else { return false }
        let visibility = ScheduleVisibility(rawValue: scheduleVisibilityRaw) ?? .off
        return visibility == .friendsOnly || visibility == .public
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Share with friend
                    NavigationLink {
                        if scheduleAlreadyShared {
                            VStack(spacing: 20) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.tint)
                                Text("你的朋友本來就可以看到呦！")
                                    .font(.title3.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                NavigationLink(destination: FriendListView()) {
                                    Label("加點好友", systemImage: "person.badge.plus")
                                }
                                .buttonStyle(.borderedProminent)
                                NavigationLink(destination: MyProfileView()) {
                                    Text("蛤？可是我不想讓他們看到耶...")
                                }
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                            }
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .navigationTitle("分享給朋友")
                            .navigationBarTitleDisplayMode(.inline)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "person.2.circle")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.tint)
                                Text("前往設定 → 帳號 → 課表分享即可更改設定")
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                NavigationLink(destination: MyProfileView()) {
                                    Label("帶我去那裡", systemImage: "arrow.right.circle")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .navigationTitle("分享給朋友")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    } label: {
                        Label("分享給朋友", systemImage: "person.2")
                    }

                    // Share with others (screenshot hint)
                    NavigationLink {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 56))
                                .foregroundStyle(.tint)
                            Text("直接截圖就可以分享囉，我相信你會截圖對吧！")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("分享給其他人")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("分享給其他人", systemImage: "square.and.arrow.up")
                    }

                    // Export to 北科盒子
                    Button {
                        ntutJSON = buildNTUTBoxJSON(courses: courses, semester: semester)
                        showingNTUTExport = true
                    } label: {
                        Label("匯出到北科盒子", systemImage: "arrow.up.forward.app")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("分享課表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(isPresented: $showingNTUTExport) {
                NTUTBoxExportSheet(json: ntutJSON)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - 北科盒子 JSON Builder

    private func buildNTUTBoxJSON(courses: [Course], semester: String) -> String {
        // Build the period definitions using FJUPeriod data
        var periodsArray = "["
        for (index, times) in FJUPeriod.periodTimes.enumerated() {
            let periodNumber = index + 1
            let periodId = FJUPeriod.periodLabel(for: periodNumber)
            let comma = index < FJUPeriod.periodTimes.count - 1 ? "," : ""
            periodsArray += "\n        { \"id\": \"\(periodId)\", \"startTime\": \"\(times.start)\", \"endTime\": \"\(times.end)\" }\(comma)"
        }
        periodsArray += "\n      ]"

        // Group courses by (name, instructor, location) to merge multi-period same-day slots
        // and collect schedule per logical course entry
        struct CourseKey: Hashable {
            let id: String
            let name: String
            let instructor: String
            let location: String
        }

        var scheduleMap: [CourseKey: [String: [String]]] = [:]
        var courseOrder: [CourseKey] = []

        for course in courses {
            let key = CourseKey(id: course.id, name: course.name, instructor: course.instructor, location: course.location)

            if scheduleMap[key] == nil {
                scheduleMap[key] = [:]
                courseOrder.append(key)
            }

            let dayEnglish = englishDayName(course.dayOfWeek)

            // Expand startPeriod...endPeriod into individual period ids
            for period in course.startPeriod...course.endPeriod {
                let pid = FJUPeriod.periodLabel(for: period)
                scheduleMap[key]?[dayEnglish, default: []].append(pid)
            }
        }

        // Build courses JSON array
        var coursesArray = "["
        for (index, key) in courseOrder.enumerated() {
            guard let daySchedule = scheduleMap[key] else { continue }

            // Build schedule object
            var scheduleObj = "{"
            let sortedDays = daySchedule.keys.sorted { englishDayOrder($0) < englishDayOrder($1) }
            for (di, day) in sortedDays.enumerated() {
                let periods = (daySchedule[day] ?? []).map { "\"\($0)\"" }.joined(separator: ", ")
                let daySep = di < sortedDays.count - 1 ? ", " : ""
                scheduleObj += "\"\(day)\": [\(periods)]\(daySep)"
            }
            scheduleObj += "}"

            let comma = index < courseOrder.count - 1 ? "," : ""
            coursesArray += """

        {
          "courseId": "\(escapeJSON(key.id))",
          "courseName": "\(escapeJSON(key.name))",
          "teacher": "\(escapeJSON(key.instructor))",
          "classroom": "\(escapeJSON(key.location))",
          "schedule": \(scheduleObj)
        }\(comma)
"""
        }
        coursesArray += "\n      ]"

        let json = """
{
  "version": 1,
  "school": "輔仁大學",
  "semester": "\(semester)",
  "timeConfig": {
    "name": "輔仁大學",
    "periods": \(periodsArray)
  },
  "courses": \(coursesArray)
}
"""
        return json
    }

    private func englishDayName(_ chinese: String) -> String {
        switch chinese {
        case "一": return "Monday"
        case "二": return "Tuesday"
        case "三": return "Wednesday"
        case "四": return "Thursday"
        case "五": return "Friday"
        case "六": return "Saturday"
        case "日": return "Sunday"
        default: return chinese
        }
    }

    private func englishDayOrder(_ day: String) -> Int {
        switch day {
        case "Monday": return 0
        case "Tuesday": return 1
        case "Wednesday": return 2
        case "Thursday": return 3
        case "Friday": return 4
        case "Saturday": return 5
        case "Sunday": return 6
        default: return 7
        }
    }

    private func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - 北科盒子 Export Sheet

private struct NTUTBoxExportSheet: View {
    let json: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("我不知道你為什麼要這樣做，但你可以把以下內容貼到匯入匯入課表裡面：")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    Text(json)
                        .font(.system(.caption, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        .textSelection(.enabled)
                }
                .padding(.vertical)
            }
            .navigationTitle("匯出到北科盒子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = json
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已複製！" : "複製 JSON", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
