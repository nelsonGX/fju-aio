import SwiftUI

struct ClassroomScheduleView: View {
    @State private var index: ClassroomScheduleIndex?
    @State private var query = ""
    @State private var exactRoom = ""
    @State private var suggestions: [String] = []
    @State private var examples: [String] = []
    @State private var selectedWeekday = ClassroomScheduleConstants.currentWeekday() ?? ClassroomScheduleConstants.weekdays[0]
    @State private var currentPeriod = ClassroomScheduleConstants.currentPeriod()
    @State private var loadState: LoadState = .loading
    @State private var errorMessage = ""
    @FocusState private var isSearchFocused: Bool

    private let service = ClassroomScheduleService.shared
    private let syncStatus = SyncStatusManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchSection

                if loadState != .loading {
                    if let index, !exactRoom.isEmpty {
                        nowResultSection(index: index, room: exactRoom)
                        weekdayPicker
                        dayScheduleSection(index: index, room: exactRoom)
                    } else {
                        suggestionsSection
                        if loadState == .error || (loadState == .ready && suggestions.isEmpty) {
                            emptyState
                        }
                    }
                    if loadState == .ready, let metadata = index?.metadata {
                        metadataFooter(metadata)
                    }
                }
            }
            .readableContent()
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("教室課表")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await withCheckedContinuation { continuation in
                Task {
                    await load(forceRefresh: true)
                    continuation.resume()
                }
            }
        }
        .task {
            updateCurrentTimeSelection()
            await load(forceRefresh: false)
        }
        .onChange(of: query) { _, newValue in
            updateQuery(newValue)
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("輸入教室代碼，例如 LI105", text: $query)
                .font(.body)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .appCard()
    }

    // MARK: - Now Result

    private func nowResultSection(index: ClassroomScheduleIndex, room: String) -> some View {
        let today = ClassroomScheduleConstants.currentWeekday()
        let period = currentPeriod
        let courses = today.flatMap { weekday in
            period.map { period in index.courses(room: room, weekday: weekday, period: period) }
        } ?? []

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(room)
                        .font(.largeTitle.weight(.bold))
                    Text(nowSubtitle(today: today, period: period))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: courses.isEmpty ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(courses.isEmpty ? .green : .orange)
            }

            if period == nil || today == nil {
                Text("目前不在可判斷的上課節次內")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if courses.isEmpty {
                Text("現在空堂")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
            } else {
                Text("現在有課")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(courses) { course in
                        simpleCourseLine(course)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func simpleCourseLine(_ course: ClassroomScheduledCourse) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.courseName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text([course.offeringUnit, course.instructor].filter { !$0.isEmpty }.joined(separator: " / "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }

    private func nowSubtitle(today: String?, period: String?) -> String {
        guard let today else {
            return "今天沒有日間課表可比對。"
        }
        guard let period else {
            return "\(today) 目前不是上課節次。"
        }
        return "\(today) \(period) \(ClassroomScheduleConstants.timeRangeText(for: period))"
    }

    // MARK: - Weekday Picker

    private var weekdayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClassroomScheduleConstants.weekdays, id: \.self) { weekday in
                    Button {
                        selectedWeekday = weekday
                    } label: {
                        Text(ClassroomScheduleConstants.shortWeekday(weekday))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(weekday == selectedWeekday ? .white : .primary)
                            .frame(width: 44, height: 36)
                        .background(
                            weekday == selectedWeekday
                                ? AppTheme.accent
                                : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Day Schedule

    private func dayScheduleSection(index: ClassroomScheduleIndex, room: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("當日課表")
                    .font(.headline)
                Spacer()
                Text(selectedWeekday)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            VStack(spacing: 6) {
                ForEach(ClassroomScheduleConstants.periods, id: \.self) { period in
                    let courses = index.courses(room: room, weekday: selectedWeekday, period: period)
                    periodRow(period: period, courses: courses, isCurrent: isCurrent(period: period))
                }
            }
        }
        .appCard()
    }

    private func periodRow(period: String, courses: [ClassroomScheduledCourse], isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(period)
                    .font(.headline.monospaced())
                Text(ClassroomScheduleConstants.periodSubcopy(period))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)

            if courses.isEmpty {
                Text("空堂")
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(courses) { course in
                        courseBlock(course, isCurrent: isCurrent)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(rowBackground(isCurrent: isCurrent), in: RoundedRectangle(cornerRadius: 8))
    }

    private func courseBlock(_ course: ClassroomScheduledCourse, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(course.week.isEmpty || course.week == "全" ? "全學期" : "\(course.week)週")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
                Text(course.courseName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            if !course.offeringUnit.isEmpty {
                Text(course.offeringUnit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !course.instructor.isEmpty {
                Text(course.instructor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !course.remarks.isEmpty {
                Text(course.remarks)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowBackground(isCurrent: Bool) -> Color {
        isCurrent ? AppTheme.accent.opacity(0.12) : Color(.tertiarySystemGroupedBackground)
    }

    private func isCurrent(period: String) -> Bool {
        selectedWeekday == ClassroomScheduleConstants.currentWeekday() && currentPeriod == period
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(query.isEmpty ? "快速開始" : "相近教室")
                    .font(.headline)
                Spacer()
                if !suggestions.isEmpty {
                    Text("\(suggestions.count) 筆")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if suggestions.isEmpty && loadState == .ready {
                Text(query.isEmpty ? "資料載入後會提供幾間教室範例。" : "沒有找到相近的教室代碼。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !suggestions.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { room in
                        Button(room) {
                            query = room
                            isSearchFocused = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .appCard()
    }

    // MARK: - Empty / Error State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: loadState == .error ? "wifi.exclamationmark" : "door.left.hand.open")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyCopy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if loadState == .error {
                Button("重試") {
                    Task { await load(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: 24)
    }

    // MARK: - Metadata Footer

    private func metadataFooter(_ metadata: ClassroomScheduleMetadata) -> some View {
        Text("\(metadata.division) · \(metadata.roomCount) 間教室 · 更新 \(generatedText(metadata))")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Data

    private func load(forceRefresh: Bool) async {
        updateCurrentTimeSelection()
        loadState = .loading
        errorMessage = ""

        do {
            let loadedIndex = try await syncStatus.withSync("正在載入教室課表…（可能會花一點時間）") {
                try await service.loadIndex(forceRefresh: forceRefresh)
            }
            index = loadedIndex
            examples = buildExamples(from: loadedIndex.rooms)
            loadState = .ready
            updateQuery(query)
        } catch {
            loadState = .error
            errorMessage = error.localizedDescription
        }
    }

    private func updateQuery(_ rawQuery: String) {
        let normalized = ClassroomScheduleConstants.normalizedRoom(rawQuery)
        if query != normalized {
            query = normalized
            return
        }

        guard let index else {
            exactRoom = ""
            suggestions = []
            return
        }

        exactRoom = index.rooms.first { $0 == normalized } ?? ""
        suggestions = normalized.isEmpty ? examples : index.suggestedRooms(for: normalized)

        if !exactRoom.isEmpty {
            WidgetDataWriter.shared.writeClassroomData(index: index, room: exactRoom)
        }

        if exactRoom.isEmpty {
            selectedWeekday = ClassroomScheduleConstants.currentWeekday() ?? ClassroomScheduleConstants.weekdays[0]
        }
    }

    private func updateCurrentTimeSelection() {
        currentPeriod = ClassroomScheduleConstants.currentPeriod()
        if let today = ClassroomScheduleConstants.currentWeekday() {
            selectedWeekday = today
        }
    }

    private func buildExamples(from rooms: [String]) -> [String] {
        var examples: [String] = []
        var seenBuildings = Set<String>()

        for room in rooms {
            let building = ClassroomScheduleConstants.buildingCode(for: room)
            if examples.count < 6, !seenBuildings.contains(building) {
                seenBuildings.insert(building)
                examples.append(room)
            }
        }

        for room in rooms where examples.count < 6 && !examples.contains(room) {
            examples.append(room)
        }

        return examples
    }

    // MARK: - Computed Strings

    private var emptyTitle: String {
        switch loadState {
        case .loading:
            return ""
        case .error:
            return "暫時無法載入課表"
        case .ready:
            return query.isEmpty ? "先查一間教室" : "沒有找到 \(query)"
        }
    }

    private var emptyCopy: String {
        switch loadState {
        case .loading:
            return ""
        case .error:
            return "請確認網路連線後再試一次。"
        case .ready:
            return query.isEmpty
                ? "輸入教室代碼，或從建議清單中點選一間教室。"
                : "請改試完整教室代碼，例如 LI105。"
        }
    }

    private func generatedText(_ metadata: ClassroomScheduleMetadata) -> String {
        guard let date = metadata.generatedDate else { return metadata.generatedAtUTC }
        return date.formatted(.dateTime.year().month().day().hour().minute())
    }

    private enum LoadState {
        case loading
        case ready
        case error
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(width: width, height: rows.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(in: bounds.width, subviews: subviews) {
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append(FlowRow(y: y, maxY: y + rowHeight, items: currentItems))
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
                currentItems = []
            }

            currentItems.append(FlowItem(subview: subview, x: x, size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(y: y, maxY: y + rowHeight, items: currentItems))
        }

        return rows
    }

    private struct FlowRow {
        let y: CGFloat
        let maxY: CGFloat
        let items: [FlowItem]
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let x: CGFloat
        let size: CGSize
    }
}
