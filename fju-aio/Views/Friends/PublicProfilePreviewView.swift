import SwiftUI

struct PublicProfilePreviewView: View {
    let profile: PublicProfile
    var avatarURL: URL? = nil

    var body: some View {
        List {
            PublicProfileHeaderSection(profile: profile, avatarURL: avatarURL ?? profile.avatarURL)
            PublicProfileInfoSections(profile: profile)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("公開資料預覽")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PublicProfileInfoSections: View {
    let profile: PublicProfile
    @State private var selectedCourse: PublicCourseInfo?

    var body: some View {
        Group {
            if let bio = profile.bio, !bio.isEmpty {
                Section("自我介紹") {
                    Text(bio)
                        .font(.subheadline)
                }
            }

            if !profile.socialLinks.isEmpty {
                Section("社群連結") {
                    ForEach(profile.socialLinks) { link in
                        PublicProfileSocialLinkRow(link: link)
                    }
                }
            }

            if let snapshot = profile.scheduleSnapshot, !snapshot.courses.isEmpty {
                Section("公開課表") {
                    PublicScheduleSummary(snapshot: snapshot)
                    PublicScheduleTimetable(
                        courses: sortedCourses(snapshot.courses),
                        accentColor: AppTheme.accent,
                        selectedCourse: $selectedCourse
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .sheet(item: $selectedCourse) { course in
            PublicCourseDetailSheet(
                course: course,
                ownerLabel: "姓名",
                ownerName: profile.displayName
            )
            .presentationDetents([.medium])
        }
    }

    private func sortedCourses(_ courses: [PublicCourseInfo]) -> [PublicCourseInfo] {
        courses.sorted {
            let dayA = dayOrder($0.dayOfWeek), dayB = dayOrder($1.dayOfWeek)
            return dayA != dayB ? dayA < dayB : $0.startPeriod < $1.startPeriod
        }
    }

    private func dayOrder(_ day: String) -> Int {
        ["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: day) ?? 99
    }
}

private struct PublicProfileHeaderSection: View {
    let profile: PublicProfile
    let avatarURL: URL?
    @State private var showAvatarMessage = false

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    ProfileAvatarView(name: profile.displayName, avatarURL: avatarURL, size: 82)
                        .onTapGesture { showAvatarMessage = true }

                    Text(profile.displayName)
                        .font(.title3.weight(.semibold))
                    Text(profile.empNo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .alert("頭貼", isPresented: $showAvatarMessage) {
                Button("確定", role: .cancel) {}
            } message: {
                Text("請前往 TronClass 更改這個頭貼")
            }
        }
    }
}

struct ProfileAvatarView: View {
    let name: String
    let avatarURL: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: avatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            default:
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(String(name.prefix(1)))
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            }
        }
    }
}

private struct PublicProfileSocialLinkRow: View {
    let link: SocialLink

    var body: some View {
        let content = HStack(spacing: 12) {
            SocialBrandIcon(platform: link.platform)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.platform.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(link.displayHandle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if link.resolvedURL != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }

        if let url = link.resolvedURL {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

struct PublicProfileScheduleView: View {
    let snapshot: FriendScheduleSnapshot
    @State private var selectedCourse: PublicCourseInfo?

    var body: some View {
        List {
            Section {
                LabeledContent("姓名", value: snapshot.ownerDisplayName)
                LabeledContent("學期", value: snapshot.semester)
                LabeledContent("更新時間", value: snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("課表") {
                PublicScheduleTimetable(
                    courses: sortedCourses(snapshot.courses),
                    accentColor: AppTheme.accent,
                    selectedCourse: $selectedCourse
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        }
        .navigationTitle("公開課表")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedCourse) { course in
            PublicCourseDetailSheet(
                course: course,
                ownerLabel: "姓名",
                ownerName: snapshot.ownerDisplayName
            )
            .presentationDetents([.medium])
        }
    }

    private func sortedCourses(_ courses: [PublicCourseInfo]) -> [PublicCourseInfo] {
        courses.sorted {
            let dayA = dayOrder($0.dayOfWeek), dayB = dayOrder($1.dayOfWeek)
            return dayA != dayB ? dayA < dayB : $0.startPeriod < $1.startPeriod
        }
    }

    private func dayOrder(_ day: String) -> Int {
        ["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: day) ?? 99
    }
}

struct PublicScheduleSummary: View {
    let snapshot: FriendScheduleSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Label("\(snapshot.semester) · \(snapshot.courses.count) 門課", systemImage: "calendar")
            Spacer(minLength: 8)
            Text(snapshot.updatedAt.formatted(date: .abbreviated, time: .omitted))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

struct PublicScheduleTimetable: View {
    let courses: [PublicCourseInfo]
    let accentColor: Color
    @Binding var selectedCourse: PublicCourseInfo?

    private let periodHeight: CGFloat = 56
    private let timeColumnWidth: CGFloat = 38
    private let displayPeriods = 1...11
    private let weekdays = Array(FJUPeriod.dayNames.prefix(5))
    private let scheduleBackground = Color(.secondarySystemGroupedBackground)

    private var todayWeekdayIndex: Int? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let index = weekday - 2
        return (0...4).contains(index) ? index : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let colWidth = dayColumnWidth(screenWidth: geometry.size.width)

            VStack(spacing: 0) {
                headerRow(colWidth: colWidth)
                gridBody(colWidth: colWidth)
            }
        }
        .frame(height: CGFloat(displayPeriods.count) * periodHeight + 36)
    }

    private func dayColumnWidth(screenWidth: CGFloat) -> CGFloat {
        max(42, (screenWidth - timeColumnWidth) / 5)
    }

    private func headerRow(colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            scheduleBackground
                .frame(width: timeColumnWidth, height: 32)

            ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(index == todayWeekdayIndex ? .white : .secondary)
                    .frame(width: colWidth, height: 28)
                    .background {
                        if index == todayWeekdayIndex {
                            Capsule()
                                .fill(accentColor)
                                .frame(width: 28, height: 28)
                        } else {
                            scheduleBackground
                        }
                    }
            }
        }
        .padding(.bottom, 4)
    }

    private func gridBody(colWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            gridBackground(colWidth: colWidth)
            courseBlocks(colWidth: colWidth)
        }
        .frame(
            width: timeColumnWidth + CGFloat(5) * colWidth,
            height: CGFloat(displayPeriods.count) * periodHeight
        )
        .background(scheduleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func gridBackground(colWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(displayPeriods), id: \.self) { period in
                HStack(spacing: 0) {
                    VStack(spacing: 1) {
                        Text(FJUPeriod.periodLabel(for: period))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(period == 5 ? Color.orange.opacity(0.8) : .secondary)
                        Text(FJUPeriod.startTime(for: period))
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: timeColumnWidth, height: periodHeight)
                    .background(scheduleBackground)

                    ForEach(0..<5, id: \.self) { dayIndex in
                        Rectangle()
                            .fill(dayIndex == todayWeekdayIndex
                                  ? accentColor.opacity(0.12)
                                  : scheduleBackground)
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
        ForEach(courses.filter { course in
            let dayNumber = publicCourseDayNumber(course.dayOfWeek)
            return dayNumber >= 1 && dayNumber <= 5 && displayPeriods.contains(course.startPeriod)
        }) { course in
            let dayIndex = publicCourseDayNumber(course.dayOfWeek) - 1
            let x = timeColumnWidth + CGFloat(dayIndex) * colWidth + 1.5
            let y = CGFloat(course.startPeriod - displayPeriods.lowerBound) * periodHeight + 1
            let height = CGFloat(course.endPeriod - course.startPeriod + 1) * periodHeight - 2

            PublicScheduleCourseBlock(
                course: course,
                color: accentColor,
                periodHeight: periodHeight
            )
            .frame(width: colWidth - 3, height: height)
            .offset(x: x, y: y)
            .onTapGesture {
                selectedCourse = course
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
}

private struct PublicScheduleCourseBlock: View {
    let course: PublicCourseInfo
    let color: Color
    let periodHeight: CGFloat

    private var cellHeight: CGFloat {
        CGFloat(course.endPeriod - course.startPeriod + 1) * periodHeight - 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(cellHeight > periodHeight ? 2 : 1)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)

            if cellHeight > periodHeight * 0.9, course.location.isEmpty == false {
                Text(course.location)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.mix(with: .white, by: 0.25).opacity(0.34),
                            color.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.75), lineWidth: 1.5)
        )
    }
}

struct PublicCourseDetailSheet: View {
    let course: PublicCourseInfo
    let ownerLabel: String
    let ownerName: String
    @Environment(\.dismiss) private var dismiss

    private var timeText: String {
        let start = FJUPeriod.periodLabel(for: course.startPeriod)
        let end = FJUPeriod.periodLabel(for: course.endPeriod)
        let periodText = start == end ? "第\(start)節" : "第\(start)-\(end)節"
        return "星期\(course.dayOfWeek) \(periodText)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(ownerLabel, value: ownerName)
                    LabeledContent("時間", value: timeText)
                    if course.location.isEmpty == false {
                        LabeledContent("教室", value: course.location)
                    }
                    if course.instructor.isEmpty == false {
                        LabeledContent("教師", value: course.instructor)
                    }
                    if course.weeks.isEmpty == false {
                        LabeledContent("週別", value: course.weeks)
                    }
                }
            }
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
