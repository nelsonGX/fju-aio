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

    private let periodHeight: CGFloat = 56
    private let timeColumnWidth: CGFloat = 38
    private let displayPeriods = 1...11
    private let cache = AppCache.shared

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
                if !availableSemesters.isEmpty {
                    Menu {
                        ForEach(availableSemesters, id: \.self) { semester in
                            Button {
                                if semester != selectedSemester {
                                    selectedSemester = semester
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
